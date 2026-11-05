import Foundation

/// Pure, deterministic state machine that turns raw mouse input into decisions and effects.
/// It never touches the system itself, so it is fully unit-testable.
/// Confined to the event-tap thread (not thread-safe by design).
final class GestureEngine {

    // MARK: Types

    enum Axis: Equatable { case horizontal, vertical }
    enum Phase: Equatable { case began, changed, ended }
    enum TimerKind: Hashable { case hold, doubleClick, zoomEnd }

    enum Effect: Equatable {
        case perform(Action)
        /// Continuous Spaces / Mission Control swipe. `delta` is in screen-fraction units.
        case dockSwipe(Axis, Phase, delta: Double)
        /// Trackpad-like scroll that follows the hand. Pixel deltas.
        case dragScroll(Phase, dx: Double, dy: Double)
        case magnify(Phase, amount: Double)
        case freezeCursor(Bool)
        /// Re-create the original click of a button we swallowed but have no click action for.
        case nativeClick(button: Int)
        case schedule(TimerKind, after: TimeInterval)
        case cancel(TimerKind)
    }

    struct Result: Equatable {
        var consume: Bool
        var effects: [Effect] = []
        static let pass = Result(consume: false)
    }

    struct ScrollInput {
        /// Wheel motion, normalized so one notch ≈ 1. Positive = wheel turned up (away from you), device direction.
        var dy: Double
        var command: Bool = false
    }

    // MARK: Tunables

    static let dragThreshold: Double = 6        // px before a press becomes a drag
    static let directionalDistance: Double = 40 // px to fire a directional action
    static let holdDelay: TimeInterval = 0.45
    static let doubleClickWindow: TimeInterval = 0.25
    static let zoomEndDelay: TimeInterval = 0.2
    static let spaceCooldown: TimeInterval = 0.3
    static let pixelsPerScreen: Double = 900    // px of drag ≈ one full dock-swipe

    // MARK: State

    var config: AppConfig

    private enum Mode: Equatable {
        case undecided
        case dock(Axis)
        case dragScroll
        case directional(fired: Bool)
        case discreteSwipe(fired: Bool)
        case holdFired
        case scrolled
    }

    private struct Press {
        var button: Int
        var binding: ButtonBinding
        var mode: Mode = .undecided
        var dx: Double = 0
        var dy: Double = 0
        var isSecondClick = false
    }

    private var press: Press?
    private var pendingClickButton: Int?
    private var scrollAccumulator: Double = 0
    private var lastSpaceSwitch: TimeInterval = -.infinity
    private var zoomActive = false

    init(config: AppConfig) {
        self.config = config
    }

    var isBusy: Bool { press != nil }

    // MARK: Input

    func buttonDown(_ button: Int, at time: TimeInterval) -> Result {
        guard config.enabled, let binding = config.binding(for: button) else { return .pass }

        var effects: [Effect] = []
        var newPress = Press(button: button, binding: binding)

        if let pending = pendingClickButton {
            effects.append(.cancel(.doubleClick))
            pendingClickButton = nil
            if pending == button {
                newPress.isSecondClick = true
            } else if let first = config.binding(for: pending) {
                effects += clickEffects(first)
            }
        }
        if press != nil { effects += finish() } // a second button pressed mid-gesture: close the first cleanly
        if binding.hold != nil { effects.append(.schedule(.hold, after: Self.holdDelay)) }

        press = newPress
        return Result(consume: true, effects: effects)
    }

    func buttonUp(_ button: Int, at time: TimeInterval) -> Result {
        guard let p = press, p.button == button else {
            // Up for a button we swallowed earlier (e.g. config changed mid-press) — keep it swallowed.
            return config.binding(for: button) != nil ? Result(consume: true) : .pass
        }
        var effects: [Effect] = []
        if p.binding.hold != nil { effects.append(.cancel(.hold)) }

        if p.mode == .undecided {
            if p.isSecondClick {
                if let a = p.binding.doubleClick { effects.append(.perform(a)) }
            } else if p.binding.doubleClick != nil {
                pendingClickButton = button
                effects.append(.schedule(.doubleClick, after: Self.doubleClickWindow))
            } else {
                effects += clickEffects(p.binding)
            }
            press = nil
        } else {
            effects += finish()
        }
        return Result(consume: true, effects: effects)
    }

    /// `dx`, `dy` are mouse deltas in pixels (CG coordinates: +y is down).
    func dragged(_ button: Int, dx: Double, dy: Double) -> Result {
        guard var p = press, p.button == button else { return .pass }
        guard let drag = p.binding.drag else {
            return Result(consume: false) // let the pointer move normally
        }
        p.dx += dx
        p.dy += dy
        var effects: [Effect] = []
        let sign: Double = config.reverseGestureDirection ? -1 : 1
        let scale = config.gestureSensitivity / Self.pixelsPerScreen

        switch p.mode {
        case .undecided:
            guard hypot(p.dx, p.dy) >= Self.dragThreshold else { press = p; return Result(consume: true) }
            if p.binding.hold != nil { effects.append(.cancel(.hold)) }
            effects.append(.freezeCursor(true))
            switch drag {
            case .spacesAndMissionControl:
                let axis: Axis = abs(p.dx) >= abs(p.dy) ? .horizontal : .vertical
                if config.fluidGestures {
                    p.mode = .dock(axis)
                    let d = axis == .horizontal ? p.dx : p.dy
                    effects.append(.dockSwipe(axis, .began, delta: d * scale * sign))
                } else {
                    p.mode = .discreteSwipe(fired: false)
                }
            case .dragToScroll:
                p.mode = .dragScroll
                effects.append(.dragScroll(.began, dx: p.dx, dy: p.dy))
            case .directional:
                p.mode = .directional(fired: false)
            }
        case .dock(let axis):
            let d = axis == .horizontal ? dx : dy
            if d != 0 { effects.append(.dockSwipe(axis, .changed, delta: d * scale * sign)) }
        case .dragScroll:
            effects.append(.dragScroll(.changed, dx: dx, dy: dy))
        default:
            break
        }

        // Discrete direction firing (custom directions, or fluid gestures turned off)
        if case .directional(fired: false) = p.mode, case .directional(let dirs) = drag,
           let action = pick(dirs, dx: p.dx, dy: p.dy) {
            p.mode = .directional(fired: true)
            if let action { effects.append(.perform(action)) }
        }
        if case .discreteSwipe(fired: false) = p.mode {
            let swipe = DirectionalActions(
                up: .missionControl, down: .appExpose,
                // Dragging right reveals the Space on the left, like a trackpad.
                left: sign > 0 ? .spaceRight : .spaceLeft,
                right: sign > 0 ? .spaceLeft : .spaceRight)
            if let action = pick(swipe, dx: p.dx, dy: p.dy) {
                p.mode = .discreteSwipe(fired: true)
                if let action { effects.append(.perform(action)) }
            }
        }

        press = p
        return Result(consume: true, effects: effects)
    }

    func scrolled(_ input: ScrollInput, at time: TimeInterval) -> Result {
        guard config.enabled else { return .pass }

        if var p = press, let binding = p.binding.scroll {
            var effects: [Effect] = []
            if p.mode == .undecided, p.binding.hold != nil { effects.append(.cancel(.hold)) }
            if p.mode == .undecided || p.mode == .holdFired { p.mode = .scrolled }
            guard p.mode == .scrolled else { return Result(consume: true) } // mid-drag: ignore wheel
            press = p
            effects += scrollEffects(binding, dy: input.dy, at: time)
            return Result(consume: true, effects: effects)
        }

        if press == nil, input.command, config.commandScrollZooms {
            return Result(consume: true, effects: scrollEffects(.zoom, dy: input.dy, at: time))
        }
        return .pass
    }

    func timerFired(_ kind: TimerKind) -> [Effect] {
        switch kind {
        case .hold:
            guard var p = press, p.mode == .undecided, let a = p.binding.hold else { return [] }
            p.mode = .holdFired
            press = p
            return [.perform(a)]
        case .doubleClick:
            guard let b = pendingClickButton else { return [] }
            pendingClickButton = nil
            return config.binding(for: b).map(clickEffects) ?? []
        case .zoomEnd:
            guard zoomActive else { return [] }
            zoomActive = false
            return [.magnify(.ended, amount: 0)]
        }
    }

    /// Abort everything (e.g. tap disabled, app disabled). Returns effects that restore the system.
    func reset() -> [Effect] {
        var effects = press != nil ? finish() : []
        if zoomActive { zoomActive = false; effects.append(.magnify(.ended, amount: 0)) }
        pendingClickButton = nil
        return effects
    }

    // MARK: Helpers

    private func clickEffects(_ binding: ButtonBinding) -> [Effect] {
        if let a = binding.click { return [.perform(a)] }
        return [.nativeClick(button: binding.button)]
    }

    /// Ends the current press's gesture.
    private func finish() -> [Effect] {
        guard let p = press else { return [] }
        press = nil
        switch p.mode {
        case .dock(let axis):
            return [.dockSwipe(axis, .ended, delta: 0), .freezeCursor(false)]
        case .dragScroll:
            return [.dragScroll(.ended, dx: 0, dy: 0), .freezeCursor(false)]
        case .directional, .discreteSwipe:
            return [.freezeCursor(false)]
        case .undecided, .holdFired, .scrolled:
            return []
        }
    }

    /// Returns `nil` while undecided, `.some(action?)` once the drag went far enough in one direction.
    private func pick(_ d: DirectionalActions, dx: Double, dy: Double) -> Action?? {
        guard max(abs(dx), abs(dy)) >= Self.directionalDistance else { return nil }
        if abs(dx) >= abs(dy) { return .some(dx > 0 ? d.right : d.left) }
        return .some(dy > 0 ? d.down : d.up)
    }

    private func scrollEffects(_ binding: ScrollBinding, dy: Double, at time: TimeInterval) -> [Effect] {
        switch binding {
        case .zoom:
            var effects: [Effect] = []
            if !zoomActive {
                zoomActive = true
                effects.append(.magnify(.began, amount: 0))
            }
            effects.append(.magnify(.changed, amount: max(-0.5, min(0.5, dy * 0.08))))
            effects.append(.cancel(.zoomEnd))
            effects.append(.schedule(.zoomEnd, after: Self.zoomEndDelay))
            return effects
        case .switchSpaces:
            return step(dy, at: time, cooldown: Self.spaceCooldown).map { up in
                [.perform(up ? .spaceRight : .spaceLeft)]
            } ?? []
        case .volume:
            return step(dy, at: time, cooldown: 0).map { [.perform($0 ? .volumeUp : .volumeDown)] } ?? []
        case .directional(let upAction, let downAction):
            guard let up = step(dy, at: time, cooldown: 0.12), let a = up ? upAction : downAction else { return [] }
            return [.perform(a)]
        }
    }

    /// Accumulates wheel motion and returns the direction once a full notch is reached (true = up).
    private func step(_ dy: Double, at time: TimeInterval, cooldown: TimeInterval) -> Bool? {
        if (scrollAccumulator > 0) != (dy > 0) { scrollAccumulator = 0 }
        scrollAccumulator += dy
        guard abs(scrollAccumulator) >= 1 else { return nil }
        let up = scrollAccumulator > 0
        scrollAccumulator = 0
        if cooldown > 0 {
            guard time - lastSpaceSwitch >= cooldown else { return nil }
            lastSpaceSwitch = time
        }
        return up
    }
}

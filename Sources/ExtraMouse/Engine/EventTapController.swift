@preconcurrency import AppKit
import CoreGraphics

/// Owns the CGEventTap and a dedicated high-priority thread that runs it.
/// Everything below `start()` runs on that thread, so the UI can never make the mouse stutter
/// and the engine never needs locks.
final class EventTapController: @unchecked Sendable {
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    // Tap-thread state
    private let engine: GestureEngine
    private var poster: EventPoster!
    private var dock: DockSwipe!
    private var performer: ActionPerformer!
    private var timers: [GestureEngine.TimerKind: CFRunLoopTimer] = [:]
    private var captureMode = false
    private var cursorFrozen = false

    init(config: AppConfig) {
        engine = GestureEngine(config: config)
        let schedule: Scheduler = { [weak self] delay, block in self?.after(delay, block) }
        poster = EventPoster(schedule: schedule)
        dock = DockSwipe(schedule: schedule)
        performer = ActionPerformer(poster: poster)
    }

    var isRunning: Bool { tap != nil }

    /// Creates the tap. Fails (returns false) when Accessibility permission is missing.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = [CGEventType.otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
            .reduce(0) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { ready.signal(); return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(self.runLoop, source, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "ExtraMouse.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        ready.wait()
        apply(enabled: engine.config.enabled)
        return true
    }

    func stop() {
        guard let tap else { return }
        perform { [self] in
            run(engine.reset())
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        self.tap = nil
        runLoop = nil
        thread = nil
    }

    func update(_ config: AppConfig) {
        perform { [self] in
            if !config.enabled { run(engine.reset()) }
            engine.config = config
        }
        apply(enabled: config.enabled)
    }

    /// While the "+" field is hovered, every click must reach the app unchanged.
    func setCaptureMode(_ on: Bool) {
        perform { [self] in
            if on { run(engine.reset()) }
            captureMode = on
        }
    }

    private func apply(enabled: Bool) {
        if let tap { CGEvent.tapEnable(tap: tap, enable: enabled) }
    }

    // MARK: Tap thread

    private func perform(_ block: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        guard let runLoop else { return }
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { _ in block() }
        CFRunLoopAddTimer(runLoop, timer, .commonModes)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            run(engine.reset())
            if let tap { CGEvent.tapEnable(tap: tap, enable: engine.config.enabled) }
            return pass
        }
        if captureMode || event.getIntegerValueField(.eventSourceUserData) == EventPoster.marker {
            return pass
        }

        let now = ProcessInfo.processInfo.systemUptime
        let result: GestureEngine.Result
        switch type {
        case .otherMouseDown:
            result = engine.buttonDown(button(event), at: now)
        case .otherMouseUp:
            result = engine.buttonUp(button(event), at: now)
        case .otherMouseDragged:
            result = engine.dragged(button(event),
                                    dx: Double(event.getIntegerValueField(.mouseEventDeltaX)),
                                    dy: Double(event.getIntegerValueField(.mouseEventDeltaY)))
        case .scrollWheel:
            return handleScroll(event, now: now)
        default:
            return pass
        }
        run(result.effects)
        return result.consume ? nil : pass
    }

    private func button(_ event: CGEvent) -> Int {
        Int(event.getIntegerValueField(.mouseEventButtonNumber))
    }

    private func handleScroll(_ event: CGEvent, now: TimeInterval) -> Unmanaged<CGEvent>? {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        // One wheel notch = ±1 (accelerated multi-line events still count as one notch).
        let lines = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let raw: Double = continuous
            ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) / 30
            : Double(lines.signum())
        // Normalize to the physical wheel direction regardless of "natural scrolling".
        let inverted = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
        let input = GestureEngine.ScrollInput(dy: inverted ? -raw : raw,
                                              command: event.flags.contains(.maskCommand))

        if raw != 0 || engine.isBusy {
            let result = engine.scrolled(input, at: now)
            run(result.effects)
            if result.consume { return nil }
        }

        // Plain wheel tweaks — only for real mouse wheels, never trackpads.
        guard !continuous, engine.config.enabled else { return Unmanaged.passUnretained(event) }
        let config = engine.config
        if config.reverseScrollDirection { reverse(event) }
        if config.shiftScrollsHorizontally, event.flags.contains(.maskShift) { swapAxes(event) }
        return Unmanaged.passUnretained(event)
    }

    private static let axisFields: [(CGEventField, CGEventField)] = [
        (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
        (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
        (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
    ]

    private func reverse(_ e: CGEvent) {
        for (a, b) in Self.axisFields {
            for f in [a, b] { e.setDoubleValueField(f, value: -e.getDoubleValueField(f)) }
        }
    }

    private func swapAxes(_ e: CGEvent) {
        for (a, b) in Self.axisFields {
            let v1 = e.getDoubleValueField(a), v2 = e.getDoubleValueField(b)
            guard v2 == 0 else { continue }
            e.setDoubleValueField(b, value: v1)
            e.setDoubleValueField(a, value: 0)
        }
    }

    private func run(_ effects: [GestureEngine.Effect]) {
        for effect in effects {
            switch effect {
            case .perform(let action):
                performer.perform(action)
            case .dockSwipe(let axis, let phase, let delta):
                dock.send(axis, phase, delta: delta)
            case .dragScroll(let phase, let dx, let dy):
                poster.dragScroll(phase, dx: dx, dy: dy)
            case .magnify(let phase, let amount):
                poster.magnify(phase, amount: amount)
            case .freezeCursor(let freeze):
                guard freeze != cursorFrozen else { continue }
                cursorFrozen = freeze
                CGAssociateMouseAndMouseCursorPosition(freeze ? 0 : 1)
            case .nativeClick(let button):
                poster.click(button: button)
            case .schedule(let kind, let delay):
                cancelTimer(kind)
                guard let runLoop else { continue }
                let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { [weak self] _ in
                    guard let self else { return }
                    self.timers[kind] = nil
                    self.run(self.engine.timerFired(kind))
                }
                timers[kind] = timer
                CFRunLoopAddTimer(runLoop, timer, .commonModes)
            case .cancel(let kind):
                cancelTimer(kind)
            }
        }
    }

    private func cancelTimer(_ kind: GestureEngine.TimerKind) {
        if let t = timers.removeValue(forKey: kind) { CFRunLoopTimerInvalidate(t) }
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(type, event)
}

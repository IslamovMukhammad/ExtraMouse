import AppKit
import CoreGraphics

/// Schedules a block on the event-tap thread's run loop.
typealias Scheduler = (_ delay: TimeInterval, _ block: @escaping () -> Void) -> Void

/// Posts synthetic input events. All events we post carry `marker` so our own tap ignores them.
/// Used only from the event-tap thread.
final class EventPoster {
    static let marker: Int64 = 0x4558_4D53 // "EXMS"

    private let schedule: Scheduler

    init(schedule: @escaping Scheduler) {
        self.schedule = schedule
    }

    private func post(_ event: CGEvent?, tap: CGEventTapLocation = .cghidEventTap) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: tap)
    }

    // MARK: Keyboard

    func key(_ keyCode: UInt16, flags: CGEventFlags = []) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
            e?.flags = flags
            post(e)
        }
    }

    /// NX_KEYTYPE_* media keys. Shows the native volume / brightness HUD.
    func mediaKey(_ code: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((code << 16) | ((down ? 0xA : 0xB) << 8))
            let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       subtype: 8, data1: data1, data2: -1)
            post(e?.cgEvent)
        }
    }

    // MARK: Mouse

    func click(button: Int) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: mouseButton)
            e?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            post(e)
        }
    }

    // MARK: Gestures

    func magnify(_ phase: GestureEngine.Phase, amount: Double) {
        guard let e = CGEvent(source: nil) else { return }
        e.set(PrivateAPI.Field.type, PrivateAPI.gestureEventType)
        e.set(PrivateAPI.Field.gestureSubtype, PrivateAPI.HID.typeZoom)
        e.set(PrivateAPI.Field.gesturePhase, Int64(phase.hidPhase.rawValue))
        e.set(PrivateAPI.Field.magnification, double: amount)
        post(e, tap: .cgSessionEventTap)
    }

    func smartZoom() {
        guard let e = CGEvent(source: nil) else { return }
        e.set(PrivateAPI.Field.type, PrivateAPI.gestureEventType)
        e.set(PrivateAPI.Field.gestureSubtype, PrivateAPI.HID.typeZoomToggle)
        post(e, tap: .cgSessionEventTap)
    }

    // MARK: Drag to scroll (with momentum)

    private var momentumGeneration = 0
    private var recent: [(dx: Double, dy: Double, t: TimeInterval)] = []

    func dragScroll(_ phase: GestureEngine.Phase, dx: Double, dy: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        switch phase {
        case .began:
            momentumGeneration += 1 // stop any running momentum
            recent = []
            postScroll(dx: dx, dy: dy, scrollPhase: 1, momentumPhase: 0)
        case .changed:
            recent.append((dx, dy, now))
            recent.removeAll { now - $0.t > 0.08 }
            postScroll(dx: dx, dy: dy, scrollPhase: 2, momentumPhase: 0)
        case .ended:
            postScroll(dx: 0, dy: 0, scrollPhase: 4, momentumPhase: 0)
            recent.removeAll { now - $0.t > 0.08 }
            // Average velocity over the last 80 ms, expressed per 1/120 s frame.
            let span = max(1.0 / 120, (recent.last?.t ?? now) - (recent.first?.t ?? now))
            let vx = recent.reduce(0) { $0 + $1.dx } / span / 120
            let vy = recent.reduce(0) { $0 + $1.dy } / span / 120
            recent = []
            if hypot(vx, vy) > 2 { startMomentum(vx: vx, vy: vy) }
        }
    }

    private func startMomentum(vx: Double, vy: Double) {
        momentumGeneration += 1
        let generation = momentumGeneration
        var v = (x: vx, y: vy)
        postScroll(dx: v.x, dy: v.y, scrollPhase: 0, momentumPhase: 1)

        func tick() {
            guard generation == momentumGeneration else { return }
            v.x *= 0.94
            v.y *= 0.94
            if hypot(v.x, v.y) < 0.4 {
                postScroll(dx: 0, dy: 0, scrollPhase: 0, momentumPhase: 3)
                return
            }
            postScroll(dx: v.x, dy: v.y, scrollPhase: 0, momentumPhase: 2)
            schedule(1.0 / 120, tick)
        }
        schedule(1.0 / 120, tick)
    }

    func cancelMomentum() { momentumGeneration += 1 }

    private func postScroll(dx: Double, dy: Double, scrollPhase: Int64, momentumPhase: Int64) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        e.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
        e.set(PrivateAPI.Field.scrollPhase, scrollPhase)
        e.set(PrivateAPI.Field.momentumPhase, momentumPhase)
        post(e, tap: .cgSessionEventTap)
    }
}

extension GestureEngine.Phase {
    var hidPhase: PrivateAPI.HID.Phase {
        switch self {
        case .began: .began
        case .changed: .changed
        case .ended: .ended
        }
    }
}

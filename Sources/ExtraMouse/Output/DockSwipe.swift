import CoreGraphics
import Foundation

/// Synthesizes the Dock's three-finger swipe (Spaces left/right, Mission Control, App Exposé)
/// so the animation follows the mouse like a real trackpad.
///
/// macOS 27+ needs a real IOHIDEvent attached to the CGEvent; older systems accept plain CGEvent fields.
final class DockSwipe {
    private let schedule: Scheduler
    private var origin: Double = 0
    private var lastDelta: Double = 0
    private var generation = 0

    init(schedule: @escaping Scheduler) {
        self.schedule = schedule
    }

    func send(_ axis: GestureEngine.Axis, _ phase: GestureEngine.Phase, delta: Double) {
        let motion = axis == .horizontal ? PrivateAPI.HID.motionHorizontal : PrivateAPI.HID.motionVertical
        var hidPhase: PrivateAPI.HID.Phase
        switch phase {
        case .began:
            generation += 1
            origin = delta
            hidPhase = .began
        case .changed:
            guard delta != 0 else { return }
            origin += delta
            hidPhase = .changed
        case .ended:
            // Finish the swipe only if the last movement still points the same way; otherwise snap back.
            hidPhase = (lastDelta == 0 || (lastDelta > 0) == (origin > 0)) ? .ended : .cancelled
        }
        if phase != .ended { lastDelta = delta }

        let exitSpeed = lastDelta * (Self.useHIDPath ? 300 : 100)
        let events = make(motion: motion, phase: hidPhase, progress: origin, exitSpeed: exitSpeed)
        events.forEach { $0.post(tap: .cgSessionEventTap) }

        // Under load the Dock sometimes drops the final event and the swipe gets stuck mid-way.
        // Re-sending it shortly after reliably unsticks it.
        if hidPhase == .ended || hidPhase == .cancelled {
            let g = generation
            for delay in [0.2, 0.5] {
                schedule(delay) { [weak self] in
                    guard let self, self.generation == g else { return }
                    events.forEach { $0.post(tap: .cgSessionEventTap) }
                }
            }
            lastDelta = 0
        }
    }

    static var useHIDPath: Bool {
        if #available(macOS 27, *) { return PrivateAPI.hidPathAvailable }
        return false
    }

    private func make(motion: Int, phase: PrivateAPI.HID.Phase, progress: Double, exitSpeed: Double) -> [CGEvent] {
        Self.useHIDPath
            ? makeHID(motion: motion, phase: phase, progress: progress, exitSpeed: exitSpeed)
            : makeLegacy(motion: motion, phase: phase, progress: progress, exitSpeed: exitSpeed)
    }

    private func makeHID(motion: Int, phase: PrivateAPI.HID.Phase, progress: Double, exitSpeed: Double) -> [CGEvent] {
        typealias H = PrivateAPI.HID
        guard let create = PrivateAPI.hidEventCreate, let setF = PrivateAPI.hidEventSetFloat,
              let setI = PrivateAPI.hidEventSetInteger, let append = PrivateAPI.hidEventAppend,
              let attach = PrivateAPI.slEventSetHIDEvent,
              let hid = create(nil, H.typeDockSwipe, mach_absolute_time(), phase.rawValue << H.phaseShift)
        else { return [] }
        defer { PrivateAPI.release(hid) }

        let base = H.fieldBase(H.typeDockSwipe)
        setI(hid, base | 1, motion)                 // Motion
        setI(hid, base | 5, H.flavorDockPrimary)    // Flavor
        setF(hid, base | 2, progress)               // Progress

        if phase == .ended || phase == .cancelled,
           let velocity = create(nil, H.typeVelocity, mach_absolute_time(), 0) {
            let vBase = H.fieldBase(H.typeVelocity)
            setF(velocity, vBase | 0, exitSpeed)
            setF(velocity, vBase | 1, exitSpeed)
            setF(velocity, vBase | 2, 0)
            append(hid, velocity, 0)
            PrivateAPI.release(velocity)
        }

        guard let event = CGEvent(source: nil) else { return [] }
        event.set(PrivateAPI.Field.type, PrivateAPI.dockControlEventType)
        attach(event, hid)
        return [event]
    }

    private func makeLegacy(motion: Int, phase: PrivateAPI.HID.Phase, progress: Double, exitSpeed: Double) -> [CGEvent] {
        guard let gesture = CGEvent(source: nil), let dock = CGEvent(source: nil) else { return [] }
        gesture.set(55, PrivateAPI.gestureEventType)
        gesture.set(41, 33231)

        dock.set(55, PrivateAPI.dockControlEventType)
        dock.set(110, Int64(PrivateAPI.HID.typeDockSwipe))
        dock.set(132, Int64(phase.rawValue))
        dock.set(134, Int64(phase.rawValue))
        dock.set(124, double: progress)
        dock.set(135, Int64(Float(progress).bitPattern))
        dock.set(41, 33231)
        // Fields 119/139 hold the swipe type encoded as a float32 bit pattern.
        let typeBits = Double(Float(bitPattern: UInt32(motion)))
        dock.set(119, double: typeBits)
        dock.set(139, double: typeBits)
        dock.set(123, Int64(motion))
        dock.set(165, Int64(motion))
        dock.set(136, 0)
        if phase == .ended || phase == .cancelled {
            dock.set(129, double: exitSpeed)
            dock.set(130, double: exitSpeed)
        }
        return [dock, gesture]
    }
}

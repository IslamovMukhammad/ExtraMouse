import CoreGraphics
import Foundation

/// Thin, failure-tolerant bindings to private macOS functions, looked up at runtime.
/// If Apple removes one, the feature silently falls back instead of crashing.
enum PrivateAPI {
    typealias HIDEventRef = UnsafeMutableRawPointer

    private static func handle(_ path: String) -> UnsafeMutableRawPointer? { dlopen(path, RTLD_LAZY) }
    nonisolated(unsafe) private static let iokit = handle("/System/Library/Frameworks/IOKit.framework/IOKit")
    nonisolated(unsafe) private static let skylight = handle("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
    nonisolated(unsafe) private static let appServices = handle("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")

    private static func sym<T>(_ lib: UnsafeMutableRawPointer?, _ name: String, as _: T.Type) -> T? {
        guard let lib, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    // IOKit — IOHIDEvent
    nonisolated(unsafe) static let hidEventCreate = sym(iokit, "IOHIDEventCreate",
        as: (@convention(c) (CFAllocator?, UInt32, UInt64, UInt32) -> HIDEventRef?).self)
    nonisolated(unsafe) static let hidEventSetFloat = sym(iokit, "IOHIDEventSetFloatValue",
        as: (@convention(c) (HIDEventRef, UInt32, Double) -> Void).self)
    nonisolated(unsafe) static let hidEventSetInteger = sym(iokit, "IOHIDEventSetIntegerValue",
        as: (@convention(c) (HIDEventRef, UInt32, Int) -> Void).self)
    nonisolated(unsafe) static let hidEventAppend = sym(iokit, "IOHIDEventAppendEvent",
        as: (@convention(c) (HIDEventRef, HIDEventRef, UInt32) -> Void).self)

    // SkyLight — attach an IOHIDEvent to a CGEvent
    nonisolated(unsafe) static let slEventSetHIDEvent = sym(skylight, "SLEventSetIOHIDEvent",
        as: (@convention(c) (CGEvent, HIDEventRef) -> Void).self)

    // Dock
    nonisolated(unsafe) static let coreDockSendNotification = sym(appServices, "CoreDockSendNotification",
        as: (@convention(c) (CFString, Int32) -> Void).self)

    static var hidPathAvailable: Bool {
        hidEventCreate != nil && hidEventSetFloat != nil && hidEventSetInteger != nil
            && hidEventAppend != nil && slEventSetHIDEvent != nil
    }

    static func release(_ ref: HIDEventRef) {
        Unmanaged<AnyObject>.fromOpaque(ref).release()
    }

    // MARK: Constants (from Apple's open-source IOHIDFamily headers)

    enum HID {
        static let typeVelocity: UInt32 = 9
        static let typeZoom: Int64 = 8
        static let typeZoomToggle: Int64 = 22
        static let typeDockSwipe: UInt32 = 23
        static func fieldBase(_ type: UInt32) -> UInt32 { type << 16 }
        static let phaseShift: UInt32 = 24
        static let flavorDockPrimary = 3
        static let motionHorizontal = 1
        static let motionVertical = 2

        enum Phase: UInt32 { case began = 1, changed = 2, ended = 4, cancelled = 8 }
    }

    // CGEvent private fields
    enum Field {
        static let type: UInt32 = 55
        static let gestureSubtype: UInt32 = 110
        static let magnification: UInt32 = 113
        static let gesturePhase: UInt32 = 132
        static let scrollPhase: UInt32 = 99
        static let momentumPhase: UInt32 = 123
        static let isContinuous: UInt32 = 88
    }

    static let gestureEventType: Int64 = 29   // NSEventTypeGesture
    static let dockControlEventType: Int64 = 30
}

extension CGEvent {
    func set(_ field: UInt32, _ value: Int64) {
        if let f = CGEventField(rawValue: field) { setIntegerValueField(f, value: value) }
    }
    func set(_ field: UInt32, double value: Double) {
        if let f = CGEventField(rawValue: field) { setDoubleValueField(f, value: value) }
    }
}

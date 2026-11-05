import AppKit
import CoreGraphics

/// Executes `Action`s. Called on the event-tap thread; hops to main only where AppKit requires it.
final class ActionPerformer {
    private let poster: EventPoster

    init(poster: EventPoster) {
        self.poster = poster
    }

    // Virtual key codes
    private enum Key {
        static let d: UInt16 = 2, equal: UInt16 = 24, minus: UInt16 = 27
        static let leftBracket: UInt16 = 33, rightBracket: UInt16 = 30
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        static let f11: UInt16 = 103
    }

    // NX_KEYTYPE_* codes
    private enum Media {
        static let soundUp: Int32 = 0, soundDown: Int32 = 1
        static let brightnessUp: Int32 = 2, brightnessDown: Int32 = 3
        static let mute: Int32 = 7, play: Int32 = 16, next: Int32 = 17, previous: Int32 = 18
    }

    /// Arrow-key hotkeys are registered with ⌃ + fn, so both flags are needed to match them.
    private let ctrlArrow: CGEventFlags = [.maskControl, .maskSecondaryFn]

    func perform(_ action: Action) {
        switch action {
        case .volumeUp: poster.mediaKey(Media.soundUp)
        case .volumeDown: poster.mediaKey(Media.soundDown)
        case .mute: poster.mediaKey(Media.mute)
        case .brightnessUp: poster.mediaKey(Media.brightnessUp)
        case .brightnessDown: poster.mediaKey(Media.brightnessDown)
        case .playPause: poster.mediaKey(Media.play)
        case .nextTrack: poster.mediaKey(Media.next)
        case .previousTrack: poster.mediaKey(Media.previous)

        case .missionControl:
            dock("com.apple.expose.awake") { poster.key(Key.up, flags: ctrlArrow) }
        case .appExpose:
            dock("com.apple.expose.front.awake") { poster.key(Key.down, flags: ctrlArrow) }
        case .showDesktop:
            dock("com.apple.showdesktop.awake") { poster.key(Key.f11, flags: .maskSecondaryFn) }
        case .launchpad:
            openLaunchpad()
        case .spaceLeft: poster.key(Key.left, flags: ctrlArrow)
        case .spaceRight: poster.key(Key.right, flags: ctrlArrow)

        case .lookUp: poster.key(Key.d, flags: [.maskControl, .maskCommand])
        case .smartZoom: poster.smartZoom()
        case .zoomIn: poster.key(Key.equal, flags: .maskCommand)
        case .zoomOut: poster.key(Key.minus, flags: .maskCommand)
        case .back: poster.key(Key.leftBracket, flags: .maskCommand)
        case .forward: poster.key(Key.rightBracket, flags: .maskCommand)
        case .middleClick: poster.click(button: 2)

        case .shortcut(let combo):
            poster.key(combo.keyCode, flags: CGEventFlags(rawValue: combo.modifiers))
        case .openApp(let path):
            DispatchQueue.main.async {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                                   configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    private func dock(_ notification: String, fallback: () -> Void) {
        if let send = PrivateAPI.coreDockSendNotification {
            send(notification as CFString, 0)
        } else {
            fallback()
        }
    }

    private func openLaunchpad() {
        DispatchQueue.main.async {
            let candidates = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
            guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

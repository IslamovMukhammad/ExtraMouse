import Foundation

/// A keyboard shortcut recorded by the user.
struct KeyCombo: Codable, Hashable, Sendable {
    var keyCode: UInt16
    /// Raw `CGEventFlags` bits for ⌘ ⌥ ⌃ ⇧ (and fn).
    var modifiers: UInt64
    /// Human readable label captured at record time, e.g. "⌘⇧T".
    var display: String
}

/// Everything a trigger can do.
enum Action: Codable, Hashable, Sendable {
    // Media
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
    case playPause, nextTrack, previousTrack
    // System
    case missionControl, appExpose, launchpad, showDesktop
    case spaceLeft, spaceRight
    // Navigation & zoom
    case lookUp, smartZoom, zoomIn, zoomOut
    case back, forward
    case middleClick
    // Custom
    case shortcut(KeyCombo)
    case openApp(path: String)

    var title: String {
        switch self {
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .missionControl: "Mission Control"
        case .appExpose: "Application Windows"
        case .launchpad: "Apps (Launchpad)"
        case .showDesktop: "Show Desktop"
        case .spaceLeft: "Move Left a Space"
        case .spaceRight: "Move Right a Space"
        case .lookUp: "Look Up & Quick Look"
        case .smartZoom: "Smart Zoom"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .back: "Back"
        case .forward: "Forward"
        case .middleClick: "Middle Click"
        case .shortcut(let combo): "Shortcut \(combo.display)"
        case .openApp(let path): "Open \(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)"
        }
    }

    var symbol: String {
        switch self {
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .mute: "speaker.slash.fill"
        case .brightnessUp: "sun.max.fill"
        case .brightnessDown: "sun.min.fill"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .missionControl: "rectangle.3.group"
        case .appExpose: "rectangle.stack"
        case .launchpad: "square.grid.3x3"
        case .showDesktop: "menubar.dock.rectangle"
        case .spaceLeft: "arrow.left.square"
        case .spaceRight: "arrow.right.square"
        case .lookUp: "text.magnifyingglass"
        case .smartZoom: "plus.magnifyingglass"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .back: "chevron.backward"
        case .forward: "chevron.forward"
        case .middleClick: "computermouse"
        case .shortcut: "command"
        case .openApp: "app"
        }
    }

    /// Fixed actions offered in pickers, grouped. Custom ones (shortcut / open app) are added by the picker itself.
    static let groups: [(String, [Action])] = [
        ("Media", [.volumeUp, .volumeDown, .mute, .playPause, .nextTrack, .previousTrack, .brightnessUp, .brightnessDown]),
        ("System", [.missionControl, .appExpose, .showDesktop, .launchpad, .spaceLeft, .spaceRight]),
        ("Navigation", [.back, .forward, .lookUp, .smartZoom, .zoomIn, .zoomOut, .middleClick]),
    ]
}

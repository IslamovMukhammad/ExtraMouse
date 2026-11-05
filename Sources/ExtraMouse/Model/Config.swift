import Foundation

struct DirectionalActions: Codable, Hashable, Sendable {
    var up: Action?
    var down: Action?
    var left: Action?
    var right: Action?
}

/// What happens while a button is held and the mouse is moved.
enum DragBinding: Codable, Hashable, Sendable {
    /// Like a three-finger swipe: left/right switches Spaces, up opens Mission Control, down shows app windows.
    case spacesAndMissionControl
    /// Grab the page and scroll it in any direction, with momentum.
    case dragToScroll
    /// One action per direction.
    case directional(DirectionalActions)

    var title: String {
        switch self {
        case .spacesAndMissionControl: "Spaces & Mission Control"
        case .dragToScroll: "Drag to Scroll"
        case .directional: "Custom Directions"
        }
    }
}

/// What happens while a button is held and the wheel is turned.
enum ScrollBinding: Codable, Hashable, Sendable {
    case zoom
    case switchSpaces
    case volume
    case directional(up: Action?, down: Action?)

    var title: String {
        switch self {
        case .zoom: "Zoom In or Out"
        case .switchSpaces: "Switch Spaces"
        case .volume: "Change Volume"
        case .directional: "Custom Directions"
        }
    }
}

enum Trigger: String, CaseIterable, Codable, Sendable {
    case click, doubleClick, hold, drag, scroll

    var title: String {
        switch self {
        case .click: "Click"
        case .doubleClick: "Double Click"
        case .hold: "Hold"
        case .drag: "Click and Drag"
        case .scroll: "Click and Scroll"
        }
    }
}

/// All triggers configured for one mouse button.
struct ButtonBinding: Codable, Hashable, Sendable, Identifiable {
    /// CoreGraphics button number. 2 = middle, 3 = "Button 4", 4 = "Button 5", …
    var button: Int
    var click: Action?
    var doubleClick: Action?
    var hold: Action?
    var drag: DragBinding?
    var scroll: ScrollBinding?

    var id: Int { button }

    var isEmpty: Bool {
        click == nil && doubleClick == nil && hold == nil && drag == nil && scroll == nil
    }

    func has(_ trigger: Trigger) -> Bool {
        switch trigger {
        case .click: click != nil
        case .doubleClick: doubleClick != nil
        case .hold: hold != nil
        case .drag: drag != nil
        case .scroll: scroll != nil
        }
    }

    static func displayName(for button: Int) -> String {
        button == 2 ? "Middle Button" : "Button \(button + 1)"
    }
}

struct AppConfig: Codable, Hashable, Sendable {
    var enabled = true
    var showMenuBarIcon = true
    var bindings: [ButtonBinding] = AppConfig.defaultBindings

    // Gestures
    /// Use real trackpad-style gestures (smooth, follows your hand). Off = plain keyboard shortcuts.
    var fluidGestures = true
    var reverseGestureDirection = false
    /// Multiplier for how far a drag moves a Spaces / Mission Control gesture.
    var gestureSensitivity: Double = 1.0

    // Scrolling
    var reverseScrollDirection = false
    var shiftScrollsHorizontally = true
    var commandScrollZooms = false

    static let defaultBindings: [ButtonBinding] = [
        ButtonBinding(button: 3, click: .volumeDown, drag: .spacesAndMissionControl, scroll: .switchSpaces),
        ButtonBinding(button: 4, click: .volumeUp, drag: .dragToScroll, scroll: .zoom),
    ]

    func binding(for button: Int) -> ButtonBinding? {
        bindings.first { $0.button == button && !$0.isEmpty }
    }

    // Decode leniently so new settings never wipe old ones.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        bindings = try c.decodeIfPresent([ButtonBinding].self, forKey: .bindings) ?? d.bindings
        fluidGestures = try c.decodeIfPresent(Bool.self, forKey: .fluidGestures) ?? d.fluidGestures
        reverseGestureDirection = try c.decodeIfPresent(Bool.self, forKey: .reverseGestureDirection) ?? d.reverseGestureDirection
        gestureSensitivity = try c.decodeIfPresent(Double.self, forKey: .gestureSensitivity) ?? d.gestureSensitivity
        reverseScrollDirection = try c.decodeIfPresent(Bool.self, forKey: .reverseScrollDirection) ?? d.reverseScrollDirection
        shiftScrollsHorizontally = try c.decodeIfPresent(Bool.self, forKey: .shiftScrollsHorizontally) ?? d.shiftScrollsHorizontally
        commandScrollZooms = try c.decodeIfPresent(Bool.self, forKey: .commandScrollZooms) ?? d.commandScrollZooms
    }
}

/// Persists the config as JSON in UserDefaults.
enum ConfigStore {
    private static let key = "config.v1"

    static func load() -> AppConfig {
        guard let data = UserDefaults.standard.data(forKey: key) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            NSLog("ExtraMouse: could not read saved settings, using defaults: \(error)")
            return AppConfig()
        }
    }

    static func save(_ config: AppConfig) {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(config), forKey: key)
        } catch {
            NSLog("ExtraMouse: could not save settings: \(error)")
        }
    }
}

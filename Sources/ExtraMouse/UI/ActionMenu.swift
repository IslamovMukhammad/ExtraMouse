import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Dropdown that picks an `Action`, including "Keyboard Shortcut…" and "Open App…".
struct ActionMenu: View {
    let action: Action?
    var allowsNone = false
    let set: (Action?) -> Void
    @State private var recording = false

    var body: some View {
        Menu {
            if allowsNone {
                Button("Nothing") { set(nil) }
                Divider()
            }
            ForEach(Action.groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1, id: \.self) { a in
                        Button { set(a) } label: { Label(a.title, systemImage: a.symbol) }
                    }
                }
            }
            Divider()
            Button("Keyboard Shortcut…", systemImage: "command") { recording = true }
            Button("Open App…", systemImage: "app") { chooseApp() }
        } label: {
            if let action {
                Label(action.title, systemImage: action.symbol)
            } else {
                Text("Nothing").foregroundStyle(.secondary)
            }
        }
        .popover(isPresented: $recording, arrowEdge: .bottom) {
            ShortcutRecorder { combo in
                recording = false
                if let combo { set(.shortcut(combo)) }
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            set(.openApp(path: url.path))
        }
    }
}

/// Captures the next key combination pressed.
private struct ShortcutRecorder: View {
    let done: (KeyCombo?) -> Void
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            Text("Press a keyboard shortcut").font(.headline)
            Text("Esc to cancel").font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { done(nil); return nil } // Esc
                done(KeyCombo(event: event))
                return nil
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

extension KeyCombo {
    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var cg: CGEventFlags = []
        var text = ""
        if flags.contains(.control) { cg.insert(.maskControl); text += "⌃" }
        if flags.contains(.option) { cg.insert(.maskAlternate); text += "⌥" }
        if flags.contains(.shift) { cg.insert(.maskShift); text += "⇧" }
        if flags.contains(.command) { cg.insert(.maskCommand); text += "⌘" }
        if event.modifierFlags.contains(.function) { cg.insert(.maskSecondaryFn) }
        text += Self.keyName(event)
        self.init(keyCode: event.keyCode, modifiers: cg.rawValue, display: text)
    }

    private static func keyName(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = special[event.keyCode] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

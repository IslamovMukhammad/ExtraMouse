import AppKit
import SwiftUI

@main
struct ExtraMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("ExtraMouse", systemImage: "computermouse.fill", isInserted: $state.config.showMenuBarIcon) {
            MenuBarContent()
                .environment(state)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Toggle("Enable ExtraMouse", isOn: $state.config.enabled)
        Divider()
        Button("Settings…") { SettingsWindow.shared.show() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit ExtraMouse") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppState.isRunningTests else { return }
        _ = AppState.shared
        // Opened by the user (not at login) → show settings, like any normal app.
        if !launchedAsLoginItem || !AppState.shared.isTrusted {
            Task { @MainActor in SettingsWindow.shared.show() }
        }
    }

    /// Double-clicking the app while it runs (e.g. with the menu bar icon hidden) opens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in SettingsWindow.shared.show() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.tap.stop()
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

/// The settings window is managed by hand so it can be reopened from anywhere (menu bar, Dock, Finder).
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            // The window follows the content's ideal size, but resizes on the next run-loop turn.
            // Letting AppKit resize it *during* layout (sizingOptions) crashes with a constraint loop.
            let root = SettingsView()
                .environment(AppState.shared)
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { [weak self] size in
                    DispatchQueue.main.async { self?.resize(to: size) }
                }
                // Pin to the top so the page doesn't slide while the window animates its height.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "ExtraMouse"
            window.contentView = host
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        #if DEBUG
        snapshotIfRequested()
        #endif
    }

    private func resize(to size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        let current = window.contentRect(forFrameRect: window.frame).size
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin.x = window.frame.midX - frame.width / 2   // keep centered horizontally
        frame.origin.y = window.frame.maxY - frame.height        // keep the top edge in place
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    #if DEBUG
    /// Developer aid: `EXTRAMOUSE_SNAPSHOT=/path/file.png` writes the window contents to a PNG.
    private func snapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["EXTRAMOUSE_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let view = self?.window?.contentView?.superview,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
    #endif
}

import AppKit
import ApplicationServices
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var config: AppConfig {
        didSet {
            guard config != oldValue else { return }
            ConfigStore.save(config)
            tap.update(config)
        }
    }

    private(set) var isTrusted = AXIsProcessTrusted()
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?

    @ObservationIgnored let tap: EventTapController
    @ObservationIgnored private var pollTimer: Timer?

    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    private init() {
        let config = ConfigStore.load()
        self.config = config
        tap = EventTapController(config: config)
        if !Self.isRunningTests { startIfPossible() }
    }

    // MARK: Permission

    func startIfPossible() {
        isTrusted = AXIsProcessTrusted()
        if isTrusted, tap.start() {
            stopPolling()
        } else {
            startPolling()
        }
    }

    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    /// Polls only while permission is missing; stops forever once granted (zero idle cost).
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let state = AppState.shared
                guard AXIsProcessTrusted() else { return }
                state.stopPolling()
                state.startIfPossible()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Bindings

    func binding(for button: Int) -> ButtonBinding? {
        config.bindings.first { $0.button == button }
    }

    /// Adds an empty section for a newly captured button (or keeps the existing one).
    func addButton(_ button: Int) {
        guard binding(for: button) == nil else { return }
        config.bindings.append(ButtonBinding(button: button))
        config.bindings.sort { $0.button < $1.button }
    }

    func update(_ button: Int, _ change: (inout ButtonBinding) -> Void) {
        guard let i = config.bindings.firstIndex(where: { $0.button == button }) else { return }
        change(&config.bindings[i])
    }

    func removeButton(_ button: Int) {
        config.bindings.removeAll { $0.button == button }
    }

    func restoreDefaults() {
        config.bindings = AppConfig.defaultBindings
    }
}

import SwiftUI

struct GeneralTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 14) {
            if !state.isTrusted { PermissionCard() }

            Card {
                ToggleRow(title: "Enable ExtraMouse",
                          subtitle: "Turns all button actions and gestures on or off.",
                          isOn: $state.config.enabled)
                    .font(.headline)
                    .disabled(!state.isTrusted)
            }

            Card {
                ToggleRow(title: "Show in Menu Bar",
                          subtitle: "When hidden, open ExtraMouse again from Applications to see this window.",
                          isOn: $state.config.showMenuBarIcon)
                Divider().padding(.leading, 16)
                ToggleRow(title: "Launch at Login",
                          isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                if let error = state.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .padding([.horizontal, .bottom], 16)
                }
            }
        }
        .padding([.horizontal, .bottom], 22)
    }
}

private struct PermissionCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text("Allow Accessibility Access")
                .font(.headline)
            Text("ExtraMouse needs Accessibility permission to read your mouse buttons and perform gestures. Turn on ExtraMouse in System Settings › Privacy & Security › Accessibility.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") { state.requestPermission() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            Text("This window updates by itself once access is granted.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 16))
    }
}

struct ScrollingTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 14) {
            Card {
                ToggleRow(title: "Reverse Direction",
                          subtitle: "Flips the mouse wheel only. Your trackpad stays as it is.",
                          isOn: $state.config.reverseScrollDirection)
            }
            Card {
                ToggleRow(title: "Hold ⇧ Shift to Scroll Horizontally",
                          isOn: $state.config.shiftScrollsHorizontally)
                Divider().padding(.leading, 16)
                ToggleRow(title: "Hold ⌘ Command to Zoom",
                          subtitle: "Pinch-to-zoom in Safari, Preview, Maps and more.",
                          isOn: $state.config.commandScrollZooms)
            }
        }
        .padding([.horizontal, .bottom], 22)
    }
}

struct AboutTab: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("ExtraMouse").font(.title2.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Turn the extra buttons on any mouse into trackpad gestures.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Free and open source · Made by Muhammad Islamov")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding([.horizontal, .bottom], 28)
        .padding(.top, 4)
    }
}

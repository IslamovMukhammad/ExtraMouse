import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, buttons, scrolling, about
    var id: Self { self }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .buttons: "computermouse"
        case .scrolling: "arrow.up.and.down"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var tab: SettingsTab = SettingsTab(rawValue: ProcessInfo.processInfo.environment["EXTRAMOUSE_TAB"] ?? "") ?? .buttons
    /// Drives only the sliding highlight. The page itself swaps instantly so it never fights the window resize.
    @State private var highlighted: SettingsTab?
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.top, 4)
                .padding(.bottom, 14)

            Group {
                switch tab {
                case .general: GeneralTab()
                case .buttons: ButtonsTab()
                case .scrolling: ScrollingTab()
                case .about: AboutTab()
                }
            }
            .frame(width: tab == .buttons ? 560 : 440)
        }
        .onAppear {
            if !state.isTrusted, ProcessInfo.processInfo.environment["EXTRAMOUSE_TAB"] == nil { tab = .general }
            highlighted = tab
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { item in
                TabButton(item: item,
                          selected: (highlighted ?? tab) == item,
                          disabled: !state.isTrusted && (item == .buttons || item == .scrolling),
                          pill: pill) {
                    guard item != tab else { return }
                    tab = item
                    withAnimation(.spring(duration: 0.38, bounce: 0.22)) { highlighted = item }
                }
            }
        }
        .padding(4)
    }
}

private struct TabButton: View {
    let item: SettingsTab
    let selected: Bool
    let disabled: Bool
    let pill: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 20)
                    .symbolEffect(.bounce.down, options: .speed(1.4), value: selected)
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(width: 72, height: 50)
            .foregroundStyle(selected ? Color.accentColor : (hovering ? Color.primary : Color.secondary))
            .contentShape(.rect)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))
                        .matchedGeometryEffect(id: "pill", in: pill)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
        .animation(.easeOut(duration: 0.2), value: selected)
    }
}

// MARK: Shared building blocks

/// A rounded, softly tinted group of rows.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.6)))
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

import SwiftUI

struct ButtonsTab: View {
    @Environment(AppState.self) private var state
    @State private var showOptions = false
    @State private var confirmRestore = false
    @State private var flashButton: Int?

    var body: some View {
        VStack(spacing: 14) {
            CaptureField { button in
                state.addButton(button)
                withAnimation(.smooth) { flashButton = button }
                Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    withAnimation(.smooth) { flashButton = nil }
                }
            }

            if state.config.bindings.isEmpty {
                Text("No buttons yet. Click an extra mouse button inside the field above.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(state.config.bindings) { binding in
                            ButtonSection(binding: binding, highlighted: flashButton == binding.button)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Options…") { showOptions = true }
                    .popover(isPresented: $showOptions, arrowEdge: .bottom) { GestureOptions() }
                Spacer()
                Button("Restore Defaults…") { confirmRestore = true }
            }
            .buttonStyle(.glass)
            .confirmationDialog("Restore the default button setup?", isPresented: $confirmRestore) {
                Button("Restore Defaults", role: .destructive) { state.restoreDefaults() }
            } message: {
                Text("Your current button actions will be replaced.")
            }
        }
        .padding([.horizontal, .bottom], 22)
    }
}

// MARK: Capture field

private struct CaptureField: View {
    @Environment(AppState.self) private var state
    var onCapture: (Int) -> Void
    @State private var hovering = false
    @State private var rejected = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: hovering ? [] : [6, 5]))
                    .foregroundStyle(hovering ? Color.accentColor : Color.secondary.opacity(0.5))
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(hovering ? Color.accentColor : .secondary)
                        .symbolEffect(.bounce, value: hovering)
                    Text(rejected ? "Left and right click can’t be changed" : (hovering ? "Now click an extra mouse button" : ""))
                        .font(.callout)
                        .foregroundStyle(rejected ? .orange : .secondary)
                        .frame(height: 18)
                }
            }
            .frame(height: 120)
            .background(hovering ? Color.accentColor.opacity(0.06) : .clear, in: .rect(cornerRadius: 16))
            .overlay(
                CaptureArea(
                    onHover: { inside in
                        withAnimation(.smooth(duration: 0.2)) { hovering = inside }
                        state.tap.setCaptureMode(inside)
                    },
                    onButton: { button in
                        if button < 2 {
                            withAnimation { rejected = true }
                            Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { rejected = false } }
                        } else {
                            onCapture(button)
                        }
                    })
            )
            .onDisappear { state.tap.setCaptureMode(false) }

            Text("Move the pointer inside the **+** field, then **click** a mouse button to set it up.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// AppKit view that sees raw mouse buttons (SwiftUI can't distinguish buttons 3, 4, 5…).
private struct CaptureArea: NSViewRepresentable {
    var onHover: (Bool) -> Void
    var onButton: (Int) -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onHover = onHover
        view.onButton = onButton
        return view
    }

    func updateNSView(_ view: CaptureNSView, context: Context) {
        view.onHover = onHover
        view.onButton = onButton
    }

    final class CaptureNSView: NSView {
        var onHover: (Bool) -> Void = { _ in }
        var onButton: (Int) -> Void = { _ in }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }
        override func otherMouseDown(with event: NSEvent) { onButton(event.buttonNumber) }
        override func mouseDown(with event: NSEvent) { onButton(0) }
        override func rightMouseDown(with event: NSEvent) { onButton(1) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: Button section

private struct ButtonSection: View {
    @Environment(AppState.self) private var state
    let binding: ButtonBinding
    var highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(ButtonBinding.displayName(for: binding.button), systemImage: "computermouse.fill")
                    .font(.headline)
                Spacer()
                let missing = Trigger.allCases.filter { !binding.has($0) }
                if !missing.isEmpty {
                    Menu {
                        ForEach(missing, id: \.self) { trigger in
                            Button(trigger.title) { add(trigger) }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .fixedSize()
                }
                Button {
                    withAnimation(.smooth) { state.removeButton(binding.button) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Remove this button")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ForEach(Trigger.allCases.filter(binding.has), id: \.self) { trigger in
                Divider().padding(.leading, 14)
                TriggerRow(button: binding.button, trigger: trigger, binding: binding)
            }
            if binding.isEmpty {
                Divider().padding(.leading, 14)
                Text("Add a trigger like Click or Click and Drag.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
        }
        .background(.quaternary.opacity(highlighted ? 1 : 0.5), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(highlighted ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: highlighted ? 2 : 1))
    }

    private func add(_ trigger: Trigger) {
        withAnimation(.smooth) {
            state.update(binding.button) { b in
                switch trigger {
                case .click: b.click = .middleClick
                case .doubleClick: b.doubleClick = .missionControl
                case .hold: b.hold = .showDesktop
                case .drag: b.drag = .spacesAndMissionControl
                case .scroll: b.scroll = .zoom
                }
            }
        }
    }
}

private struct TriggerRow: View {
    @Environment(AppState.self) private var state
    let button: Int
    let trigger: Trigger
    let binding: ButtonBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.smooth) { state.update(button) { remove(&$0) } }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
                Text(trigger.title)
                Spacer()
                picker.frame(width: 250, alignment: .trailing)
            }
            subRows
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder private var picker: some View {
        switch trigger {
        case .click:
            ActionMenu(action: binding.click) { a in state.update(button) { $0.click = a } }
        case .doubleClick:
            ActionMenu(action: binding.doubleClick) { a in state.update(button) { $0.doubleClick = a } }
        case .hold:
            ActionMenu(action: binding.hold) { a in state.update(button) { $0.hold = a } }
        case .drag:
            Menu(binding.drag?.title ?? "") {
                Button(DragBinding.spacesAndMissionControl.title) { setDrag(.spacesAndMissionControl) }
                Button(DragBinding.dragToScroll.title) { setDrag(.dragToScroll) }
                Divider()
                Button("Custom Directions") {
                    setDrag(.directional(DirectionalActions(up: .missionControl, down: .appExpose,
                                                            left: .spaceRight, right: .spaceLeft)))
                }
            }
        case .scroll:
            Menu(binding.scroll?.title ?? "") {
                Button(ScrollBinding.zoom.title) { setScroll(.zoom) }
                Button(ScrollBinding.switchSpaces.title) { setScroll(.switchSpaces) }
                Button(ScrollBinding.volume.title) { setScroll(.volume) }
                Divider()
                Button("Custom Directions") { setScroll(.directional(up: .volumeUp, down: .volumeDown)) }
            }
        }
    }

    @ViewBuilder private var subRows: some View {
        if trigger == .drag, case .directional(let d) = binding.drag {
            DirectionRow(symbol: "arrow.up", title: "Up", action: d.up) { a in updateDirs { $0.up = a } }
            DirectionRow(symbol: "arrow.down", title: "Down", action: d.down) { a in updateDirs { $0.down = a } }
            DirectionRow(symbol: "arrow.left", title: "Left", action: d.left) { a in updateDirs { $0.left = a } }
            DirectionRow(symbol: "arrow.right", title: "Right", action: d.right) { a in updateDirs { $0.right = a } }
        }
        if trigger == .scroll, case .directional(let up, let down) = binding.scroll {
            DirectionRow(symbol: "arrow.up", title: "Wheel Up", action: up) { a in setScroll(.directional(up: a, down: down)) }
            DirectionRow(symbol: "arrow.down", title: "Wheel Down", action: down) { a in setScroll(.directional(up: up, down: a)) }
        }
    }

    private func setDrag(_ d: DragBinding) { state.update(button) { $0.drag = d } }
    private func setScroll(_ s: ScrollBinding) { state.update(button) { $0.scroll = s } }

    private func updateDirs(_ change: (inout DirectionalActions) -> Void) {
        guard case .directional(var d) = binding.drag else { return }
        change(&d)
        setDrag(.directional(d))
    }

    private func remove(_ b: inout ButtonBinding) {
        switch trigger {
        case .click: b.click = nil
        case .doubleClick: b.doubleClick = nil
        case .hold: b.hold = nil
        case .drag: b.drag = nil
        case .scroll: b.scroll = nil
        }
    }
}

private struct DirectionRow: View {
    let symbol: String
    let title: String
    let action: Action?
    let set: (Action?) -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
                .padding(.leading, 26)
            Spacer()
            ActionMenu(action: action, allowsNone: true, set: set)
                .frame(width: 250, alignment: .trailing)
        }
    }
}

// MARK: Gesture options

private struct GestureOptions: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Toggle(isOn: $state.config.fluidGestures) {
                Text("Fluid Gestures")
                Text("Spaces and Mission Control follow your hand like on a trackpad. Turn off to use simple keyboard shortcuts instead.")
            }
            Toggle(isOn: $state.config.reverseGestureDirection) {
                Text("Reverse Drag Direction")
            }
            LabeledContent("Sensitivity") {
                Slider(value: $state.config.gestureSensitivity, in: 0.4...2.5) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                .frame(width: 180)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

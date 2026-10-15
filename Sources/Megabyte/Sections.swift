import SwiftUI

enum PanelSection: String, CaseIterable, Identifiable {
    case picture, gaming, gameAssist, pip, input, monitor

    var id: Self { self }

    var title: String {
        switch self {
        case .picture: "Picture"
        case .gaming: "Gaming"
        case .gameAssist: "Game Assist"
        case .pip: "Picture in Picture"
        case .input: "Input & KVM"
        case .monitor: "Monitor"
        }
    }

    var shortTitle: String {
        switch self {
        case .pip: "PiP / PbP"
        case .input: "Input"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .picture: "camera.filters"
        case .gaming: "gamecontroller.fill"
        case .gameAssist: "scope"
        case .pip: "pip.fill"
        case .input: "cable.connector"
        case .monitor: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .picture: .orange
        case .gaming: .red
        case .gameAssist: .purple
        case .pip: .blue
        case .input: .green
        case .monitor: .gray
        }
    }
}

/// Control Center style module tiles.
struct ModuleGrid: View {
    @Environment(MonitorStore.self) private var store
    let open: (PanelSection) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(PanelSection.allCases) { section in
                Button { open(section) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(section.tint.gradient, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(section.shortTitle)
                                .font(.callout.weight(.semibold))
                            Text(summary(section))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(TileButtonStyle())
            }
        }
    }

    private func summary(_ section: PanelSection) -> String {
        func on(_ s: Setting) -> Bool { (store.value(s) ?? 0) != 0 }
        switch section {
        case .picture:
            return [store.title(.colorTemperature), store.value(.gamma) == 0 ? "Gamma Off" : store.title(.gamma)].compactMap { $0 }.joined(separator: " · ")
        case .gaming:
            return [store.title(.overdrive), on(.freeSync) ? "FreeSync" : on(.aimStabilizer) ? "Aim Stab." : nil]
                .compactMap { $0 }.joined(separator: " · ")
        case .gameAssist:
            let active = [on(.gameTimer) ? "Timer" : nil, on(.counter) ? "Counter" : nil,
                          on(.dashboard) ? "Dashboard" : nil].compactMap { $0 }
            return active.isEmpty ? "Off" : active.joined(separator: " · ")
        case .pip:
            return store.title(.pipMode) ?? ""
        case .input:
            return store.title(.input) ?? ""
        case .monitor:
            return store.title(.led).map { "LED \($0)" } ?? ""
        }
    }
}

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct DetailPage: View {
    let section: PanelSection
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: back) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: section.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(section.tint.gradient, in: Circle())
                    Text(section.title)
                        .font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            VStack(alignment: .leading, spacing: 9) {
                content
            }
            .padding(12)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .picture: PictureSection()
        case .gaming: GamingSection()
        case .gameAssist: GameAssistSection()
        case .pip: PIPSection()
        case .input: InputSection()
        case .monitor: MonitorSection()
        }
    }
}

// MARK: Rows

private struct SliderRow: View {
    @Environment(MonitorStore.self) private var store
    let title: String
    let setting: Setting
    var tint: Color? = nil

    var body: some View {
        let value = store.value(setting)
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 104, alignment: .leading)
            Slider(value: store.doubleBinding(setting), in: 0...Double(store.maximum(setting)))
                .tint(tint)
            Text(value.map(String.init) ?? "–")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .font(.callout)
        .controlSize(.small)
        .redacted(reason: value == nil ? .placeholder : [])
    }
}

private struct PickerRow: View {
    @Environment(MonitorStore.self) private var store
    let title: String
    let setting: Setting

    var body: some View {
        LabeledRow(title) {
            Picker(title, selection: store.binding(setting)) {
                ForEach(setting.options, id: \.value) { Text($0.title).tag($0.value) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .redacted(reason: store.value(setting) == nil ? .placeholder : [])
    }
}

private struct ToggleRow: View {
    @Environment(MonitorStore.self) private var store
    let title: String
    let setting: Setting

    var body: some View {
        LabeledRow(title) {
            Toggle(title, isOn: store.boolBinding(setting))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .redacted(reason: store.value(setting) == nil ? .placeholder : [])
    }
}

private struct LabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            content
        }
        .font(.callout)
        .controlSize(.small)
    }
}

// MARK: Sections

private struct PictureSection: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        SliderRow(title: "Sharpness", setting: .sharpness)
        SliderRow(title: "Black eQualizer", setting: .blackEqualizer)
        SliderRow(title: "Color Vibrance", setting: .colorVibrance)
        SliderRow(title: "Low Blue Light", setting: .lowBlueLight)
        PickerRow(title: "Gamma", setting: .gamma)
        PickerRow(title: "Color Temperature", setting: .colorTemperature)
        if store.value(.colorTemperature) == 3 {
            SliderRow(title: "Red", setting: .userRed, tint: .red)
            SliderRow(title: "Green", setting: .userGreen, tint: .green)
            SliderRow(title: "Blue", setting: .userBlue, tint: .blue)
        }
        PickerRow(title: "Super Resolution", setting: .superResolution)
        LabeledRow("Picture Mode") {
            Button("Reset") { store.resetPictureMode() }
        }
    }
}

private struct GamingSection: View {
    var body: some View {
        PickerRow(title: "Overdrive", setting: .overdrive)
        ToggleRow(title: "Aim Stabilizer", setting: .aimStabilizer)
        ToggleRow(title: "FreeSync Premium Pro", setting: .freeSync)
        ToggleRow(title: "Refresh Rate", setting: .refreshRate)
        ToggleRow(title: "Crosshair", setting: .crosshair)
    }
}

private struct GameAssistSection: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let timerMode = store.value(.gameTimer) ?? 0

        LabeledRow("Timer") {
            if timerMode == 0 {
                Stepper("\(store.timerMinutes) min", value: Binding(get: { store.timerMinutes }, set: { store.timerMinutes = $0 }), in: 1...99)
                    .monospacedDigit()
                Menu("Start") {
                    Button("Count Up") { store.startTimer(countDown: false) }
                    Button("Count Down") { store.startTimer(countDown: true) }
                }
                .fixedSize()
            } else {
                Button(store.timerRunning ? "Pause" : "Resume") { store.toggleTimerPause() }
                Button("Stop") { store.stopTimer() }
            }
        }
        LabeledRow("Counter") {
            if store.value(.counter) == 1 {
                Button("", systemImage: "minus") { store.stepCounter(-1) }
                Text("\(store.value(.counterValue) ?? 0)")
                    .monospacedDigit()
                    .frame(minWidth: 20)
                Button("", systemImage: "plus") { store.stepCounter(1) }
            }
            Toggle("Counter", isOn: store.boolBinding(.counter))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        LabeledRow("Timer & Counter Position") {
            Picker("Position", selection: Binding(get: { store.overlayCorner }, set: { store.overlayCorner = $0 })) {
                Text("Top Left").tag(0)
                Text("Middle Left").tag(1)
                Text("Bottom Left").tag(2)
                Text("Top Right").tag(3)
                Text("Middle Right").tag(4)
                Text("Bottom Right").tag(5)
            }
            .labelsHidden()
            .fixedSize()
        }
        Divider()
        ToggleRow(title: "Dashboard", setting: .dashboard)
        if store.value(.dashboard) == 1 {
            PickerRow(title: "Dashboard Position", setting: .dashboardLocation)
            LabeledRow("Show Mac CPU & GPU Load") {
                Toggle("Mac load", isOn: Binding(get: { store.feedMacStats }, set: { store.feedMacStats = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}

private struct PIPSection: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        LabeledRow("Mode") {
            Picker("Mode", selection: store.binding(.pipMode)) {
                ForEach(Setting.pipMode.options, id: \.value) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        if (store.value(.pipMode) ?? 0) != 0 {
            PickerRow(title: "Source", setting: .pipSource)
            if store.value(.pipMode) == 1 {
                PickerRow(title: "Size", setting: .pipSize)
                PickerRow(title: "Location", setting: .pipLocation)
            }
            PickerRow(title: "Audio", setting: .audioInput)
            LabeledRow("Swap") {
                Button("Display") { store.swapPIP() }
                Button("Audio") { store.swapPIPAudio() }
            }
        }
    }
}

private struct InputSection: View {
    var body: some View {
        PickerRow(title: "Input", setting: .input)
        PickerRow(title: "KVM USB", setting: .kvm)
        PickerRow(title: "USB-B Follows", setting: .kvmUSBBInput)
        PickerRow(title: "USB-C Follows", setting: .kvmUSBCInput)
    }
}

private struct MonitorSection: View {
    var body: some View {
        PickerRow(title: "OSD Transparency", setting: .osdTransparency)
        PickerRow(title: "OSD Display Time", setting: .osdTime)
        PickerRow(title: "LED Indicator", setting: .led)
        Divider()
        PickerRow(title: "Quick Switch Up", setting: .quickUp)
        PickerRow(title: "Quick Switch Down", setting: .quickDown)
        PickerRow(title: "Quick Switch Left", setting: .quickLeft)
        PickerRow(title: "Quick Switch Right", setting: .quickRight)
        Divider()
        LabeledRow("OSD Remote") { JoystickPad() }
    }
}

/// The monitor's 5-way joystick, for driving its own on-screen menu.
private struct JoystickPad: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        ZStack {
            Circle()
                .fill(.quaternary)
            key(.up, "chevron.up").offset(y: -22)
            key(.down, "chevron.down").offset(y: 22)
            key(.left, "chevron.left").offset(x: -22)
            key(.right, "chevron.right").offset(x: 22)
            Button { store.press(.center) } label: {
                Circle()
                    .fill(.background)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 68, height: 68)
    }

    private func key(_ key: MonitorStore.JoystickKey, _ symbol: String) -> some View {
        Button { store.press(key) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

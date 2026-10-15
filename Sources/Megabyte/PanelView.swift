import SwiftUI

struct PanelView: View {
    @Environment(MonitorStore.self) private var store
    private let page: State<PanelSection?>

    init(page: PanelSection? = nil) {
        self.page = State(initialValue: page)
    }

    var body: some View {
        VStack(spacing: 12) {
            MonitorHero()
            if let section = page.wrappedValue {
                DetailPage(section: section) { go(nil) }
                    .transition(.push(from: .trailing))
            } else {
                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        LevelSlider(setting: .brightness, symbol: "sun.max.fill")
                        LevelSlider(setting: .contrast, symbol: "circle.lefthalf.filled")
                        LevelSlider(setting: .volume, symbol: "speaker.wave.3.fill")
                    }
                    PictureModeStrip()
                    ModuleGrid { go($0) }
                    FooterView()
                }
                .disabled(!store.connected)
                .transition(.push(from: .leading))
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { store.refresh() }
    }

    private func go(_ section: PanelSection?) {
        withAnimation(.smooth(duration: 0.3)) { page.wrappedValue = section }
    }
}

// MARK: Hero

/// A live miniature of the M28U: the screen shows what the panel is doing right now.
private struct MonitorHero: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let level = store.connected ? Double(store.value(.brightness) ?? 0) / 100 : 0
        let tint = ScreenLook.whitePoint(store)
        VStack(spacing: 0) {
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [tint.opacity(0.2 + 0.45 * level), .clear],
                                         center: .center, startRadius: 0, endRadius: 140))
                    .frame(width: 300, height: 130)
                    .offset(y: 6)
                MonitorTwin(level: level, tint: tint)
            }
            .frame(height: 138)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Gigabyte \(store.model)")
                        .font(.system(.headline, design: .rounded))
                    if !store.connected {
                        Text("Not connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if store.isLoading {
                    ProgressView().controlSize(.mini)
                }
                if store.connected, let input = store.title(.input) {
                    Label(input, systemImage: "cable.connector")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.fill.tertiary, in: Capsule())
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.fill.quinary)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.6)))
        }
    }
}

private struct MonitorTwin: View {
    @Environment(MonitorStore.self) private var store
    let level: Double
    let tint: Color

    private let screen = CGSize(width: 200, height: 112.5)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(white: 0.08))
                screenContent
                    .frame(width: screen.width - 8, height: screen.height - 8)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            }
            .frame(width: screen.width, height: screen.height)
            .shadow(color: tint.opacity(0.55 * level), radius: 6 + 10 * level)
            // Stand: neck and foot.
            Rectangle()
                .fill(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 18, height: 14)
            Capsule()
                .fill(Color(white: 0.25))
                .frame(width: 70, height: 4)
        }
        .animation(.smooth(duration: 0.4), value: level)
        .animation(.smooth(duration: 0.4), value: tint)
        .keyframeAnimator(initialValue: 1.0, trigger: store.pulse) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.025, duration: 0.1)
            SpringKeyframe(1.0, duration: 0.35)
        }
    }

    private var screenContent: some View {
        let mode = store.value(.pictureMode) ?? 0
        return ZStack {
            Color.black
            ScreenLook.gradient(mode: mode)
                .opacity(0.15 + 0.85 * level)
            tint.opacity(0.25).blendMode(.multiply)
            // Glass reflection.
            LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .topLeading, endPoint: .center)
            Text(store.title(.pictureMode) ?? "")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 3)
                .contentTransition(.opacity)
            overlays
        }
        .animation(.smooth(duration: 0.4), value: mode)
    }

    @ViewBuilder private var overlays: some View {
        let on = { (s: Setting) in (store.value(s) ?? 0) != 0 }
        if on(.crosshair) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.red)
                .offset(y: 16)
        }
        if on(.dashboard) {
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.75)).frame(width: 18, height: 3)
                }
            }
            .padding(3)
            .background(.black.opacity(0.45), in: Capsule())
            .frame(maxHeight: .infinity, alignment: store.value(.dashboardLocation) == 0 ? .top : .bottom)
            .padding(4)
        }
        if on(.gameTimer) || on(.counter) || on(.refreshRate) {
            let corner = store.overlayCorner
            Text(on(.counter) ? "\(store.value(.counterValue) ?? 0)" : on(.gameTimer) ? "00:00" : "144")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: Alignment(horizontal: corner >= 3 ? .trailing : .leading,
                                            vertical: [.top, .center, .bottom][corner % 3]))
                .padding(5)
        }
        switch store.value(.pipMode) ?? 0 {
        case 1:
            let location = store.value(.pipLocation) ?? 3
            let scale = [0.42, 0.33, 0.25][min(2, store.value(.pipSize) ?? 1)]
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
                .frame(width: 192 * scale, height: 104 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: Alignment(horizontal: location % 2 == 0 ? .leading : .trailing,
                                            vertical: location < 2 ? .top : .bottom))
                .padding(5)
        case 2:
            Rectangle()
                .fill(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(maxWidth: .infinity)
                .padding(.leading, 96)
        default:
            EmptyView()
        }
    }
}

enum ScreenLook {
    /// A decorative palette per picture mode.
    static func colors(mode: Int) -> [Color] {
        switch mode {
        case 1: [Color(red: 0.0, green: 0.85, blue: 1.0), Color(red: 0.1, green: 0.3, blue: 0.95)]
        case 2: [Color(red: 0.25, green: 0.9, blue: 0.55), Color(red: 0.05, green: 0.45, blue: 0.5)]
        case 3: [Color(red: 1.0, green: 0.55, blue: 0.2), Color(red: 0.55, green: 0.08, blue: 0.25)]
        case 4: [Color(red: 0.98, green: 0.9, blue: 0.72), Color(red: 0.8, green: 0.62, blue: 0.4)]
        case 5: [Color(white: 0.85), Color(red: 0.45, green: 0.5, blue: 0.6)]
        case 6: [Color(red: 1.0, green: 0.4, blue: 0.7), Color(red: 0.45, green: 0.2, blue: 0.9)]
        case 7: [Color(red: 1.0, green: 0.8, blue: 0.2), Color(red: 1.0, green: 0.35, blue: 0.3)]
        case 8: [Color(red: 0.6, green: 0.95, blue: 0.9), Color(red: 0.3, green: 0.4, blue: 1.0)]
        default: [Color(red: 0.45, green: 0.65, blue: 1.0), Color(red: 0.55, green: 0.3, blue: 0.95)]
        }
    }

    static func gradient(mode: Int) -> LinearGradient {
        LinearGradient(colors: colors(mode: mode), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @MainActor static func whitePoint(_ store: MonitorStore) -> Color {
        switch store.value(.colorTemperature) {
        case 0: Color(red: 0.7, green: 0.82, blue: 1.0)
        case 2: Color(red: 1.0, green: 0.8, blue: 0.58)
        case 3:
            Color(red: Double(store.value(.userRed) ?? 100) / 100,
                  green: Double(store.value(.userGreen) ?? 100) / 100,
                  blue: Double(store.value(.userBlue) ?? 100) / 100)
        default: Color(red: 0.92, green: 0.94, blue: 1.0)
        }
    }
}

// MARK: Sliders

/// Control Center style level slider.
private struct LevelSlider: View {
    @Environment(MonitorStore.self) private var store
    let setting: Setting
    let symbol: String

    var body: some View {
        let maximum = Double(store.maximum(setting))
        let value = Double(store.value(setting) ?? 0)
        let fraction = maximum > 0 ? value / maximum : 0
        GeometryReader { geometry in
            let height = geometry.size.height
            let fill = height + (geometry.size.width - height) * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                Capsule()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                    .frame(width: fill)
                Image(systemName: symbol, variableValue: fraction)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.35))
                    .frame(width: height)
                Text("\(Int(value))")
                    .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(fraction > 0.88 ? AnyShapeStyle(Color(white: 0.35)) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText(value: value))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let x = (drag.location.x - height / 2) / max(1, geometry.size.width - height)
                store.set(setting, Int((min(1, max(0, x)) * maximum).rounded()))
            })
        }
        .frame(height: 30)
        .animation(.snappy(duration: 0.15), value: value)
        .redacted(reason: store.value(setting) == nil && store.connected ? .placeholder : [])
    }
}

// MARK: Picture modes

private struct PictureModeStrip: View {
    @Environment(MonitorStore.self) private var store
    @Namespace private var ring

    var body: some View {
        let current = store.value(.pictureMode)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Setting.pictureMode.options, id: \.value) { option in
                    let selected = option.value == current
                    Button {
                        store.set(.pictureMode, option.value)
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(ScreenLook.gradient(mode: option.value))
                                .overlay(alignment: .topLeading) {
                                    LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .center)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .frame(width: 54, height: 34)
                                .padding(2.5)
                                .overlay {
                                    if selected {
                                        RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                            .strokeBorder(Color.accentColor, lineWidth: 2)
                                            .matchedGeometryEffect(id: "ring", in: ring)
                                    }
                                }
                            Text(option.title)
                                .font(.caption2.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .animation(.snappy(duration: 0.3), value: current)
    }
}

// MARK: Footer

private struct FooterView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.loadAll() } }
                .disabled(store.isLoading)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
    }
}

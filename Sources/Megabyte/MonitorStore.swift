import Foundation
import Observation
import SwiftUI

@Observable @MainActor
final class MonitorStore {
    enum JoystickKey: UInt16 { case center = 0xe05f, up = 0xe060, down = 0xe061, right = 0xe062, left = 0xe063 }

    private(set) var connected = false
    private(set) var model = "M28U"
    private(set) var values: [Setting: Int] = [:]
    private(set) var maxima: [Setting: Int] = [:]
    private(set) var isLoading = false
    /// Bumps on every successful write so the header can react.
    private(set) var pulse = 0

    var timerMinutes = 5
    var overlayCorner: Int = UserDefaults.standard.integer(forKey: "overlayCorner") {
        didSet { UserDefaults.standard.set(overlayCorner, forKey: "overlayCorner"); sendOverlayCorner() }
    }
    var feedMacStats: Bool = UserDefaults.standard.bool(forKey: "feedMacStats") {
        didSet { UserDefaults.standard.set(feedMacStats, forKey: "feedMacStats"); updateFeed() }
    }
    var timerRunning = false

    private let hid = HIDBridge()
    private let link: DDCLink
    private var pending: [Setting: Int] = [:]
    private var writers: Set<Setting> = []
    private var loadTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private let stats = SystemStats()

    init() {
        link = DDCLink(hid: hid)
        hid.onConnectionChange = { [weak self] connected in self?.connectionChanged(connected) }
        connectionChanged(hid.isConnected)
    }

    // MARK: Values

    func value(_ setting: Setting) -> Int? { values[setting] }

    func title(_ setting: Setting) -> String? {
        guard let value = values[setting] else { return nil }
        return setting.options.first { $0.value == value }?.title
    }

    func maximum(_ setting: Setting) -> Int {
        maxima[setting] ?? (setting == .osdTime ? 30 : 100)
    }

    func binding(_ setting: Setting) -> Binding<Int> {
        Binding(get: { self.values[setting] ?? 0 }, set: { self.set(setting, $0) })
    }

    func doubleBinding(_ setting: Setting) -> Binding<Double> {
        Binding(get: { Double(self.values[setting] ?? 0) }, set: { self.set(setting, Int($0.rounded())) })
    }

    func boolBinding(_ setting: Setting) -> Binding<Bool> {
        Binding(get: { (self.values[setting] ?? 0) != 0 }, set: { self.set(setting, $0 ? 1 : 0) })
    }

    /// Records the value immediately and streams the latest one to the monitor.
    func set(_ setting: Setting, _ value: Int) {
        guard values[setting] != value || !setting.verifiesWrite else { return }
        values[setting] = value
        pending[setting] = value
        guard !writers.contains(setting) else { return }
        writers.insert(setting)
        Task { await drain(setting) }
    }

    private func drain(_ setting: Setting) async {
        defer { writers.remove(setting) }
        var attempts = 0
        while true {
            while let value = pending.removeValue(forKey: setting) {
                if await link.write(setting.code, setting.encode(value)) { pulse &+= 1 }
            }
            guard setting.verifiesWrite, attempts < 2, let wanted = values[setting] else { break }
            try? await Task.sleep(for: .milliseconds(250))
            guard pending[setting] == nil else { continue }
            guard let reading = await link.read(setting.readCode) else { break }
            if reading.value == wanted || pending[setting] != nil { break }
            attempts += 1
            pending[setting] = wanted
        }
        await followUp(after: setting)
    }

    /// Some settings change others on the monitor; re-read those.
    private func followUp(after setting: Setting) async {
        switch setting {
        case .pictureMode: await reload(Setting.pictureDependent)
        case .colorTemperature: await reload([.userRed, .userGreen, .userBlue])
        case .freeSync, .aimStabilizer: await reload([.freeSync, .aimStabilizer, .overdrive])
        case .pipMode: await reload([.pipSource, .pipSize, .pipLocation, .audioInput])
        default: break
        }
    }

    // MARK: Loading

    private func connectionChanged(_ isConnected: Bool) {
        connected = isConnected
        loadTask?.cancel()
        if isConnected {
            loadTask = Task { await loadAll() }
        }
        updateFeed()
    }

    func refresh() {
        guard connected, !isLoading else { return }
        loadTask = Task { await reload(Setting.primary) }
    }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        if let name = await link.readString(VCPCode(0xe05e)), !name.isEmpty { model = name }
        await reload(Setting.primary)
        await reload(Setting.allCases.filter { !Setting.primary.contains($0) })
        timerRunning = (values[.gameTimer] ?? 0) != 0
    }

    private func reload(_ settings: [Setting]) async {
        for setting in settings {
            guard !Task.isCancelled, connected else { return }
            guard pending[setting] == nil, !writers.contains(setting) else { continue }
            if let reading = await link.read(setting.readCode), pending[setting] == nil {
                values[setting] = reading.value
                maxima[setting] = reading.maximum
            }
        }
    }

    // MARK: Actions

    func press(_ key: JoystickKey) {
        Task { _ = await link.write(VCPCode(key.rawValue), 1) }
    }

    func resetPictureMode() {
        Task {
            _ = await link.write(VCPCode(0xe04c), 1)
            try? await Task.sleep(for: .milliseconds(400))
            await reload(Setting.pictureDependent)
        }
    }

    func swapPIP() { Task { _ = await link.write(VCPCode(0xe010), 1) } }

    func swapPIPAudio() { Task { _ = await link.write(VCPCode(0xe013), 1) } }

    func startTimer(countDown: Bool) {
        let minutes = countDown ? timerMinutes : 0
        Task {
            _ = await link.write(VCPCode(0xe027), 0)
            _ = await link.send([0xe0, 0x26, UInt8(minutes), 0])
            _ = await link.write(Setting.gameTimer.code, countDown ? 2 : 1)
            _ = await link.write(VCPCode(0xe027), 1)
            values[.gameTimer] = countDown ? 2 : 1
            timerRunning = true
        }
    }

    func toggleTimerPause() {
        timerRunning.toggle()
        let run = timerRunning
        Task { _ = await link.write(VCPCode(0xe027), run ? 1 : 0) }
    }

    func stopTimer() {
        timerRunning = false
        set(.gameTimer, 0)
    }

    func stepCounter(_ delta: Int) {
        let next = min(99, max(0, (values[.counterValue] ?? 0) + delta))
        set(.counterValue, next)
    }

    private func sendOverlayCorner() {
        // 2B takes x (0 left, 1 right) and y (0 top, 1 center, 2 bottom).
        let x = UInt8(overlayCorner / 3), y = UInt8(overlayCorner % 3)
        Task { _ = await link.send([0xe0, 0x2b, x, y]) }
    }

    // MARK: Dashboard feed

    private func updateFeed() {
        feedTask?.cancel()
        guard feedMacStats, connected else { return }
        feedTask = Task {
            // Show only CPU usage (44) and GPU usage (48) on the dashboard.
            for item: UInt8 in 0x40...0x48 {
                _ = await link.send([0xe0, item, 0, item == 0x44 || item == 0x48 ? 1 : 0])
            }
            while !Task.isCancelled {
                let sample = stats.sample()
                _ = await link.send(Self.dashboardValue(0x1d, sample.cpu))
                _ = await link.send(Self.dashboardValue(0x21, sample.gpu))
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// `E0 <code> <n/10000> <n%10000/100> <n%100> <negative>`
    private static func dashboardValue(_ code: UInt8, _ value: Int) -> [UInt8] {
        let n = abs(value)
        return [0xe0, code, UInt8(n / 10000), UInt8(n % 10000 / 100), UInt8(n % 100), value < 0 ? 1 : 0]
    }
}

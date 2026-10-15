import Foundation

/// Every readable/writable control OSD Sidekick exposes for the M28U.
enum Setting: String, CaseIterable, Sendable {
    case brightness, contrast, volume
    case pictureMode, input
    case sharpness, blackEqualizer, colorVibrance, lowBlueLight, gamma, colorTemperature
    case userRed, userGreen, userBlue
    case overdrive, superResolution, aimStabilizer, freeSync
    case crosshair, refreshRate, dashboard, dashboardLocation, gameTimer, counter, counterValue
    case pipMode, pipSource, pipSize, pipLocation, audioInput
    case kvm, kvmUSBBInput, kvmUSBCInput
    case osdTransparency, osdTime, led
    case quickUp, quickDown, quickLeft, quickRight

    var code: VCPCode {
        switch self {
        case .brightness: VCPCode(0x10)
        case .contrast: VCPCode(0x12)
        case .volume: VCPCode(0x62)
        case .sharpness: VCPCode(0x87)
        case .blackEqualizer: VCPCode(0xe002)
        case .colorTemperature: VCPCode(0xe003)
        case .userRed: VCPCode(0xe004)
        case .userGreen: VCPCode(0xe005)
        case .userBlue: VCPCode(0xe006)
        case .gamma: VCPCode(0xe007)
        case .colorVibrance: VCPCode(0xe008)
        case .overdrive: VCPCode(0xe009)
        case .aimStabilizer: VCPCode(0xe00a)
        case .lowBlueLight: VCPCode(0xe00b)
        case .freeSync: VCPCode(0xe00c)
        case .superResolution: VCPCode(0xe00d)
        case .pipMode: VCPCode(0xe00e)
        case .pipSource: VCPCode(0xe00f)
        case .pipSize: VCPCode(0xe014)
        case .pipLocation: VCPCode(0xe015)
        case .dashboard: VCPCode(0xe018)
        case .dashboardLocation: VCPCode(0xe019)
        case .refreshRate: VCPCode(0xe022)
        case .gameTimer: VCPCode(0xe023)
        case .counter: VCPCode(0xe028)
        case .counterValue: VCPCode(0xe02a)
        case .pictureMode: VCPCode(0xe02c)
        case .input: VCPCode(0xe02d)
        case .audioInput: VCPCode(0xe02e)
        case .osdTransparency: VCPCode(0xe02f)
        case .osdTime: VCPCode(0xe030)
        case .led: VCPCode(0xe031)
        case .quickUp: VCPCode(0xe032)
        case .quickDown: VCPCode(0xe033)
        case .quickRight: VCPCode(0xe034)
        case .quickLeft: VCPCode(0xe035)
        case .crosshair: VCPCode(0xe037)
        case .kvm: VCPCode(0xe069)
        case .kvmUSBBInput: VCPCode(0xe06b)
        case .kvmUSBCInput: VCPCode(0xe06c)
        }
    }

    /// The counter is set through 2A but its live value is read from 29.
    var readCode: VCPCode { self == .counterValue ? VCPCode(0xe029) : code }

    /// Display time is written as a 0–5 step but reads back in seconds.
    func encode(_ value: Int) -> Int { self == .osdTime ? max(0, value / 5 - 1) : value }

    /// Writes whose effect can't be read back right away (or that move the link elsewhere).
    var verifiesWrite: Bool {
        switch self {
        case .input, .kvm, .counterValue: false
        default: true
        }
    }

    var options: [Option] {
        switch self {
        case .pictureMode:
            Option.list("Standard", "FPS", "RTS/RPG", "Movie", "Reader", "sRGB", "Custom 1", "Custom 2", "Custom 3")
        case .input, .pipSource, .kvmUSBBInput, .kvmUSBCInput:
            Option.list("HDMI 1", "HDMI 2", "DisplayPort", "USB-C")
        case .gamma: Option.list("Off", "Gamma 1", "Gamma 2", "Gamma 3", "Gamma 4", "Gamma 5")
        case .colorTemperature: Option.list("Cool", "Normal", "Warm", "User")
        case .overdrive: Option.list("Off", "Smart OD", "Picture Quality", "Balance", "Speed")
        case .superResolution: Option.list("Off", "1", "2", "3", "4")
        case .gameTimer: Option.list("Off", "Count Up", "Count Down")
        case .pipMode: Option.list("Off", "PIP", "PBP")
        case .pipSize: Option.list("Large", "Medium", "Small")
        case .pipLocation: Option.list("Top Left", "Top Right", "Bottom Left", "Bottom Right")
        case .audioInput: Option.list("Main", "PIP/PBP", "Auto")
        case .dashboardLocation: Option.list("Top", "Bottom")
        case .kvm: Option.list("USB-B", "USB-C")
        case .osdTransparency: Option.list("0%", "20%", "40%", "60%", "80%")
        case .osdTime: [5, 10, 15, 20, 25, 30].map { Option(value: $0, title: "\($0) s") }
        case .led: Option.list("On", "Off", "Standby")
        case .quickUp, .quickDown, .quickLeft, .quickRight:
            Option.list("Aim Stabilizer", "Black eQualizer", "Low Blue Light", "Volume",
                        "Input", "Contrast", "Brightness", "Picture Mode")
        default: []
        }
    }
}

struct Option: Hashable, Sendable {
    let value: Int
    let title: String

    static func list(_ titles: String...) -> [Option] {
        titles.enumerated().map { Option(value: $0.offset, title: $0.element) }
    }
}

/// Settings grouped by how urgently the popover needs them.
extension Setting {
    static let primary: [Setting] = [.brightness, .contrast, .volume, .pictureMode, .input, .colorTemperature]
    static let pictureDependent: [Setting] = [
        .brightness, .contrast, .sharpness, .blackEqualizer, .colorVibrance, .lowBlueLight, .gamma,
        .colorTemperature, .overdrive, .superResolution, .aimStabilizer, .freeSync,
        .userRed, .userGreen, .userBlue,
    ]
}

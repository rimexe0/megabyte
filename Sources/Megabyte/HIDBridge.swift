import Foundation
import IOKit.hid

/// USB HID link to the Realtek bridge inside the M28U (0bda:1100).
///
/// Mirrors RtHIDLib.dll from OSD Sidekick: every I2C transfer to the scaler (0x6E)
/// is wrapped in a 192-byte output report; reads come back through GetInputReport.
final class HIDBridge: @unchecked Sendable {
    static let vendorID = 0x0bda
    static let productID = 0x1100
    private static let reportSize = 192
    private static let scalerAddress: UInt8 = 0x6e

    private let lock = NSLock()
    private var device: IOHIDDevice?
    private let manager: IOHIDManager

    /// Called on the main thread when the monitor appears or disappears.
    var onConnectionChange: (@MainActor (Bool) -> Void)?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<HIDBridge>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<HIDBridge>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    var isConnected: Bool { lock.withLock { device != nil } }

    private func attach(_ newDevice: IOHIDDevice) {
        guard IOHIDDeviceOpen(newDevice, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        lock.withLock { device = newDevice }
        notify(true)
    }

    private func detach(_ oldDevice: IOHIDDevice) {
        let removed = lock.withLock { () -> Bool in
            guard device == oldDevice else { return false }
            device = nil
            return true
        }
        if removed { notify(false) }
    }

    private func notify(_ connected: Bool) {
        MainActor.assumeIsolated { onConnectionChange?(connected) }
    }

    private func sendReport(_ report: [UInt8]) -> Bool {
        guard let device = lock.withLock({ device }) else { return false }
        var buffer = report
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &buffer, buffer.count) == kIOReturnSuccess
    }

    /// `HID_i2cwrite`: header `40 c6 00 00 00 00 <len> 00 | 6e 00 80`, payload at 0x40.
    func i2cWrite(_ payload: [UInt8]) -> Bool {
        var report = [UInt8](repeating: 0, count: Self.reportSize)
        report[0] = 0x40
        report[1] = 0xc6
        report[6] = UInt8(payload.count)
        report[8] = Self.scalerAddress
        report[10] = 0x80
        report.replaceSubrange(0x40..<(0x40 + payload.count), with: payload)
        return sendReport(report)
    }

    /// `HID_i2cread`: header `40 d6 51 00 00 00 <len> 00 | 6e 01 80`, then GetInputReport.
    func i2cRead(length: Int, settle: useconds_t) -> [UInt8]? {
        var report = [UInt8](repeating: 0, count: Self.reportSize)
        report[0] = 0x40
        report[1] = 0xd6
        report[2] = 0x51
        report[6] = UInt8(length)
        report[8] = Self.scalerAddress
        report[9] = 0x01
        report[10] = 0x80
        guard sendReport(report) else { return nil }
        usleep(settle)
        guard let device = lock.withLock({ device }) else { return nil }
        var buffer = [UInt8](repeating: 0, count: Self.reportSize)
        var count = buffer.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 0, &buffer, &count) == kIOReturnSuccess else {
            return nil
        }
        return Array(buffer.prefix(min(count, length)))
    }
}

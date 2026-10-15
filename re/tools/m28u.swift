// M28U control over the Realtek USB HID bridge (0bda:1100).
// Usage: m28u get <code> | m28u set <code> <value> | m28u test
// <code> is hex: "10" for standard VCP, "e02c" for Gigabyte E0 codes.
import Foundation
import IOKit.hid

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: 0x0bda, kIOHIDProductIDKey: 0x1100] as CFDictionary)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
guard let dev = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>)?.first,
      IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
    FileHandle.standardError.write("M28U HID device not available\n".data(using: .utf8)!); exit(1)
}

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

func setOut(_ rep: [UInt8]) -> Bool {
    var buf = rep
    return IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, &buf, buf.count) == kIOReturnSuccess
}

func i2cWrite(_ data: [UInt8]) -> Bool {
    var rep = [UInt8](repeating: 0, count: 192)
    rep[0] = 0x40; rep[1] = 0xc6; rep[6] = UInt8(data.count)
    rep[8] = 0x6e; rep[10] = 0x80
    for (i, b) in data.enumerated() { rep[0x40 + i] = b }
    return setOut(rep)
}

func i2cRead(_ len: Int) -> [UInt8]? {
    var rep = [UInt8](repeating: 0, count: 192)
    rep[0] = 0x40; rep[1] = 0xd6; rep[2] = 0x51; rep[6] = UInt8(len)
    rep[8] = 0x6e; rep[9] = 0x01; rep[10] = 0x80
    guard setOut(rep) else { return nil }
    usleep(100_000)
    var buf = [UInt8](repeating: 0, count: 192)
    var n = buf.count
    guard IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, 0, &buf, &n) == kIOReturnSuccess else { return nil }
    return Array(buf[0..<min(n, len)])
}

func codeBytes(_ code: UInt16) -> [UInt8] { code > 0xff ? [UInt8(code >> 8), UInt8(code & 0xff)] : [UInt8(code)] }

/// Returns (current, max, raw reply).
func get(_ code: UInt16) -> (Int, Int, [UInt8])? {
    let cb = codeBytes(code)
    for _ in 0..<3 {
        var msg: [UInt8] = [0x51, UInt8(0x81 + cb.count), 0x01] + cb
        msg.append(msg.reduce(0, ^))
        guard i2cWrite(msg) else { return nil }
        usleep(150_000)
        guard let r = i2cRead(36) else { return nil }
        if r[0] == 0x6e && r[4] == cb[0] && (cb.count == 1 || r[5] == cb[1]) {
            return (Int(r[8]) << 8 | Int(r[9]), Int(r[6]) << 8 | Int(r[7]), r)
        }
        usleep(150_000)
    }
    return nil
}

func set(_ code: UInt16, _ value: Int) -> Bool {
    var msg: [UInt8]
    if code > 0xff {
        msg = [0x51, 0x85, 0x03] + codeBytes(code) + [UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    } else {
        msg = [0x51, 0x84, 0x03, UInt8(code), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }
    msg.append(msg.reduce(0, ^))
    return i2cWrite(msg)
}

// Codes whose write can be verified by reading back, with a test value to try.
let autoTests: [(String, UInt16, Int)] = [
    ("brightness", 0x10, 35), ("contrast", 0x12, 55), ("volume", 0x62, 10), ("sharpness", 0x87, 4),
    ("black-eq", 0xe002, 12), ("color-temp", 0xe003, 2), ("gamma", 0xe007, 4), ("vibrance", 0xe008, 12),
    ("overdrive", 0xe009, 1), ("low-blue", 0xe00b, 2), ("freesync", 0xe00c, -1), ("aim-stab", 0xe00a, -1),
    ("super-res", 0xe00d, 1), ("pip-size", 0xe014, 1), ("pip-loc", 0xe015, 2), ("dash-loc", 0xe019, -1),
    ("audio-in", 0xe02e, -1), ("osd-trans", 0xe02f, 1), ("osd-time", 0xe030, 2), ("led", 0xe031, 2),
    ("quick-up", 0xe032, 3), ("quick-down", 0xe033, 3), ("quick-right", 0xe034, 3), ("quick-left", 0xe035, 3),
    ("kvm-usbb-input", 0xe06b, -1), ("kvm-typec-input", 0xe06c, -1),
    ("user-r", 0xe004, 90), ("user-g", 0xe005, 90), ("user-b", 0xe006, 90),
]

func parseCode(_ s: String) -> UInt16 { UInt16(s.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16)! }

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "get":
    let c = parseCode(args[2])
    if let (cur, mx, raw) = get(c) { print("cur=\(cur) max=\(mx) raw=\(hex(Array(raw[0..<12])))") } else { print("no reply"); exit(1) }
case "set":
    print(set(parseCode(args[2]), Int(args[3])!) ? "ok" : "write failed")
case "setraw":
    // Sidekick's long form: 51 (81+n) 03 <n bytes>, checksum XOR
    let body = args[2...].map { UInt8($0, radix: 16)! }
    var msg: [UInt8] = [0x51, UInt8(0x81 + body.count), 0x03] + body
    msg.append(msg.reduce(0, ^))
    print(i2cWrite(msg) ? "ok" : "write failed")
case "test":
    for (name, code, tv) in autoTests {
        guard let (orig, mx, _) = get(code) else { print("\(name): no reply"); continue }
        // -1 means: flip within 0...max (toggle-ish)
        let target = tv >= 0 ? (tv == orig ? max(0, tv - 1) : tv) : (orig == 0 ? 1 : 0)
        guard set(code, target) else { print("\(name): write failed"); continue }
        usleep(250_000)
        let after = get(code)?.0 ?? -999
        _ = set(code, orig)
        usleep(250_000)
        let restored = get(code)?.0 ?? -999
        let ok = after == target && restored == orig
        print(String(format: "%@ %-16@ orig=%d max=%d set=%d readback=%d restored=%d", ok ? "PASS" : "FAIL",
                     name as NSString, orig, mx, target, after, restored))
    }
default:
    print("usage: m28u get <hexcode> | set <hexcode> <value> | test")
}

// Read-only probe: sends DDC/CI "Get VCP" requests to the M28U through its
// Realtek USB HID bridge (0bda:1100), framed the same way RtHIDLib.dll does.
import Foundation
import IOKit.hid

let vid = 0x0bda, pid = 0x1100
let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: vid, kIOHIDProductIDKey: pid] as CFDictionary)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>, let dev = devs.first else {
    print("device not found"); exit(1)
}
let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
guard r == kIOReturnSuccess else { print("open failed", String(r, radix: 16)); exit(1) }

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

func setOut(_ report: [UInt8]) -> IOReturn {
    var buf = report
    return IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, &buf, buf.count)
}

// HID_i2cwrite: 40 c6 00 00 00 00 len 00 | slave 00 80 | data at 0x40
func i2cWrite(_ data: [UInt8]) -> IOReturn {
    var rep = [UInt8](repeating: 0, count: 192)
    rep[0] = 0x40; rep[1] = 0xc6; rep[6] = UInt8(data.count)
    rep[8] = 0x6e; rep[9] = 0x00; rep[10] = 0x80
    for (i, b) in data.enumerated() { rep[0x40 + i] = b }
    return setOut(rep)
}

// HID_i2cread: 40 d6 <reg addr LE32> len 00 | slave reglen 80, then GetInputReport
func i2cRead(len: Int) -> [UInt8]? {
    var rep = [UInt8](repeating: 0, count: 192)
    rep[0] = 0x40; rep[1] = 0xd6; rep[2] = 0x51; rep[6] = UInt8(len)
    rep[8] = 0x6e; rep[9] = 0x01; rep[10] = 0x80
    let w = setOut(rep)
    guard w == kIOReturnSuccess else { print("read-req failed", String(w, radix: 16)); return nil }
    usleep(100_000)
    var inBuf = [UInt8](repeating: 0, count: 192)
    var n = inBuf.count
    let g = IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, 0, &inBuf, &n)
    guard g == kIOReturnSuccess else { print("get-input failed", String(g, radix: 16)); return nil }
    return Array(inBuf[0..<min(n, len)])
}

func getVCP(_ code: [UInt8]) -> [UInt8]? {
    var msg: [UInt8] = [0x51, UInt8(0x81 + code.count), 0x01] + code
    msg.append(msg.reduce(0, ^))
    let w = i2cWrite(msg)
    guard w == kIOReturnSuccess else { print("write failed", String(w, radix: 16)); return nil }
    usleep(150_000)
    return i2cRead(len: 36)
}

let probes: [(String, [UInt8])] = [
    ("brightness 0x10", [0x10]),
    ("contrast 0x12", [0x12]),
    ("picture mode E0 2C", [0xe0, 0x2c]),
    ("input E0 2D", [0xe0, 0x2d]),
    ("soc model E0 5E", [0xe0, 0x5e]),
]
for (name, code) in probes {
    if let r = getVCP(code) {
        let v = r.count > 9 ? (Int(r[8]) << 8 | Int(r[9])) : -1
        print("\(name): value[8..9]=\(v)  raw=\(hex(r))")
    }
    usleep(150_000)
}

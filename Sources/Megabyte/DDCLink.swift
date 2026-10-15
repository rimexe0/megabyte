import Foundation

/// A VCP code. Values above 0xFF are Gigabyte's `E0 xx` codes.
struct VCPCode: Hashable, Sendable {
    let raw: UInt16
    init(_ raw: UInt16) { self.raw = raw }
    var bytes: [UInt8] { raw > 0xff ? [UInt8(raw >> 8), UInt8(raw & 0xff)] : [UInt8(raw)] }
}

struct VCPReading: Sendable {
    let value: Int
    let maximum: Int
}

/// DDC/CI over the HID bridge. All transfers run one at a time on a private queue,
/// paced so the scaler does not drop commands sent back to back.
final class DDCLink: @unchecked Sendable {
    let hid: HIDBridge
    private let queue = DispatchQueue(label: "megabyte.ddc", qos: .userInitiated)
    private var lastTransfer = DispatchTime(uptimeNanoseconds: 0)
    private static let minimumGap: UInt64 = 120_000_000

    init(hid: HIDBridge) { self.hid = hid }

    func read(_ code: VCPCode) async -> VCPReading? {
        await run {
            // 6e 88 02 00 <code...> maxH maxL curH curL
            guard let reply = self.blockingReply(code) else { return nil }
            return VCPReading(value: Int(reply[8]) << 8 | Int(reply[9]),
                              maximum: Int(reply[6]) << 8 | Int(reply[7]))
        }
    }

    /// Codes like E0 5E (model name) answer with ASCII after the code bytes.
    func readString(_ code: VCPCode) async -> String? {
        await run {
            guard let reply = self.blockingReply(code) else { return nil }
            let text = reply.dropFirst(7).prefix { (0x20...0x7e).contains($0) }
            return String(decoding: text, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }
    }

    func write(_ code: VCPCode, _ value: Int) async -> Bool {
        await send(code.bytes + [UInt8((value >> 8) & 0xff), UInt8(value & 0xff)])
    }

    /// Writes `51 (81+n) 03 <body> <xor>`, the Set VCP form Sidekick uses for every length.
    func send(_ body: [UInt8]) async -> Bool {
        await run { self.blockingSend(body) }
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private func pace() {
        let next = lastTransfer.uptimeNanoseconds + Self.minimumGap
        let now = DispatchTime.now().uptimeNanoseconds
        if next > now { usleep(useconds_t((next - now) / 1000)) }
    }

    private func blockingSend(_ body: [UInt8]) -> Bool {
        pace()
        defer { lastTransfer = .now() }
        var message: [UInt8] = [0x51, UInt8(0x81 + body.count), 0x03] + body
        message.append(message.reduce(0, ^))
        return hid.i2cWrite(message)
    }

    private func blockingReply(_ code: VCPCode) -> [UInt8]? {
        let codeBytes = code.bytes
        for _ in 0..<3 {
            pace()
            var request: [UInt8] = [0x51, UInt8(0x81 + codeBytes.count), 0x01] + codeBytes
            request.append(request.reduce(0, ^))
            guard hid.i2cWrite(request) else { lastTransfer = .now(); return nil }
            usleep(90_000)
            let reply = hid.i2cRead(length: 16, settle: 70_000)
            lastTransfer = .now()
            if let reply, reply.count >= 12, reply[0] == 0x6e, reply[3] == 0x00, reply[4] == codeBytes[0],
               codeBytes.count == 1 || reply[5] == codeBytes[1] {
                return reply
            }
            usleep(120_000)
        }
        return nil
    }
}

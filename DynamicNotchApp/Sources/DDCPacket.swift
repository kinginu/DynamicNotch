// DDC/CI message encoding for the Displays widget (2026-10-20). Pure value code (no IOKit):
// written from the VESA DDC/CI 1.1 and MCCS 2.x message formats, checked against two DELL P3225QE
// monitors on this Mac (read-only Get VCP / Capabilities replies, docs/displays.md §3).
//
// Framing (7-bit I2C address 0x37; the write address is 0x6E, the host's source address 0x51):
//   host → display   [0x6E] [0x51] [0x80 | n] [n payload bytes] [checksum]
//   display → host   [0x6E] [0x80 | n] [n payload bytes] [checksum]
// The host checksum is the XOR of every byte before it, *including* 0x6E and 0x51. A reply's
// checksum uses the virtual host address 0x50 in place of the destination byte.
// Apple Silicon's IOAVServiceWriteI2C takes the chip address (0x37) and the sub-address (0x51)
// as arguments, so `DDCPacket.message(_:)` returns the bytes from the length byte on.
import Foundation

/// MCCS VCP feature codes the widget uses.
enum VCPCode: UInt8, CaseIterable, Codable, Hashable, Sendable {
    case brightness = 0x10
    case contrast = 0x12
    case inputSource = 0x60
    case audioVolume = 0x62
}

enum DDCAddress {
    /// 7-bit I2C address of a monitor's DDC/CI interface.
    static let display7Bit: UInt8 = 0x37
    /// 8-bit write address (0x37 << 1): first byte of the bus message and of every reply.
    static let displayWrite: UInt8 = 0x6E
    /// Source address of host messages (also the I2C sub-address IOAVService writes to).
    static let host: UInt8 = 0x51
    /// Virtual host address used in the checksum of replies.
    static let hostReply: UInt8 = 0x50
}

enum DDCOpcode: UInt8, Sendable {
    case getVCP = 0x01
    case getVCPReply = 0x02
    case setVCP = 0x03
    case capabilitiesReply = 0xE3
    case capabilitiesRequest = 0xF3
}

enum DDCPacketError: Error, Equatable, Sendable {
    /// Fewer bytes than the header + length byte announce.
    case truncated
    /// First reply byte is not 0x6E (bus idle: often 0x00 / 0xFF).
    case badSource(UInt8)
    /// The length byte lacks the 0x80 marker or exceeds the buffer.
    case badLength(UInt8)
    case badChecksum(expected: UInt8, actual: UInt8)
    /// "Null message" (length 0): the display is busy or does not support the request.
    case nullReply
    case unexpectedOpcode(UInt8)
    /// The reply is for another VCP code (a stale reply on the bus).
    case codeMismatch(expected: UInt8, actual: UInt8)
    /// The display answered "unsupported VCP code" (result code 0x01).
    case unsupportedCode(UInt8)
    /// Capabilities fragment for another offset.
    case offsetMismatch(expected: UInt16, actual: UInt16)
    /// Payload longer than DDC/CI allows (32 bytes per message).
    case payloadTooLong(Int)
}

/// A parsed Get VCP Feature reply.
struct VCPReply: Equatable, Hashable, Sendable {
    var code: UInt8
    /// 0x00 = set parameter, 0x01 = momentary.
    var type: UInt8
    var maximum: UInt16
    var current: UInt16

    /// `current / maximum`, clamped to 0…1 (nil when the display reports a maximum of 0).
    var fraction: Double? {
        guard maximum > 0 else { return nil }
        return min(max(Double(current) / Double(maximum), 0), 1)
    }
}

enum DDCPacket {
    /// Largest payload (opcode + arguments) of one DDC/CI message.
    static let maxPayload = 32
    /// Length of a Get VCP Feature reply: source, length, 8 payload bytes, checksum.
    static let vcpReplyLength = 11
    /// Bytes read per capabilities fragment (source, length, opcode, offset ×2, ≤32 data, checksum).
    static let capabilitiesReplyLength = 38

    static func checksum<S: Sequence>(_ bytes: S, seed: UInt8) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(seed, ^)
    }

    /// Host → display message for IOAVServiceWriteI2C(chip 0x37, sub-address 0x51): the length
    /// byte, the payload and the checksum (seeded with 0x6E ^ 0x51).
    static func message(_ payload: [UInt8]) throws -> [UInt8] {
        guard payload.count <= maxPayload else { throw DDCPacketError.payloadTooLong(payload.count) }
        var bytes = [0x80 | UInt8(payload.count)] + payload
        bytes.append(checksum(bytes, seed: DDCAddress.displayWrite ^ DDCAddress.host))
        return bytes
    }

    /// The whole bus message including the two address bytes (for logs and tests).
    static func busMessage(_ payload: [UInt8]) throws -> [UInt8] {
        [DDCAddress.displayWrite, DDCAddress.host] + (try message(payload))
    }

    /// Get VCP Feature request: `82 01 <code> <chk>`.
    static func getVCP(_ code: UInt8) -> [UInt8] {
        // a 2-byte payload is always within maxPayload
        (try? message([DDCOpcode.getVCP.rawValue, code])) ?? []
    }

    /// Set VCP Feature request: `84 03 <code> <hi> <lo> <chk>`.
    static func setVCP(_ code: UInt8, value: UInt16) -> [UInt8] {
        (try? message([DDCOpcode.setVCP.rawValue, code, UInt8(value >> 8), UInt8(value & 0xFF)])) ?? []
    }

    /// Capabilities Request: `83 F3 <offset hi> <offset lo> <chk>`.
    static func capabilitiesRequest(offset: UInt16) -> [UInt8] {
        (try? message([DDCOpcode.capabilitiesRequest.rawValue, UInt8(offset >> 8), UInt8(offset & 0xFF)])) ?? []
    }

    /// Opcode of a host message produced by `message(_:)` (nil when malformed).
    static func opcode(ofMessage bytes: [UInt8]) -> UInt8? {
        bytes.count >= 3 ? bytes[1] : nil
    }

    /// Validates the reply framing and returns its payload (opcode first).
    static func replyPayload(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count >= 3 else { throw DDCPacketError.truncated }
        guard bytes[0] == DDCAddress.displayWrite else { throw DDCPacketError.badSource(bytes[0]) }
        guard bytes[1] & 0x80 != 0 else { throw DDCPacketError.badLength(bytes[1]) }
        let n = Int(bytes[1] & 0x7F)
        guard n <= maxPayload else { throw DDCPacketError.badLength(bytes[1]) }
        guard bytes.count >= 2 + n + 1 else { throw DDCPacketError.truncated }
        let expected = checksum(bytes[0..<(2 + n)], seed: DDCAddress.hostReply)
        let actual = bytes[2 + n]
        guard expected == actual else { throw DDCPacketError.badChecksum(expected: expected, actual: actual) }
        guard n > 0 else { throw DDCPacketError.nullReply }
        return Array(bytes[2..<(2 + n)])
    }

    /// Parses a Get VCP Feature reply (`6E 88 02 <result> <code> <type> <max hi> <max lo> <cur hi> <cur lo> <chk>`).
    static func parseVCPReply(_ bytes: [UInt8], expecting code: UInt8) throws -> VCPReply {
        let p = try replyPayload(bytes)
        guard p[0] == DDCOpcode.getVCPReply.rawValue else { throw DDCPacketError.unexpectedOpcode(p[0]) }
        guard p.count >= 8 else { throw DDCPacketError.truncated }
        if p[1] != 0x00 { throw DDCPacketError.unsupportedCode(p[2]) }
        guard p[2] == code else { throw DDCPacketError.codeMismatch(expected: code, actual: p[2]) }
        return VCPReply(code: p[2], type: p[3],
                        maximum: UInt16(p[4]) << 8 | UInt16(p[5]),
                        current: UInt16(p[6]) << 8 | UInt16(p[7]))
    }

    /// Parses one Capabilities Reply fragment (`6E 80|n E3 <offset hi> <offset lo> <data…> <chk>`).
    /// Returns the data bytes (empty = end of the string).
    static func parseCapabilitiesReply(_ bytes: [UInt8], expectingOffset offset: UInt16) throws -> [UInt8] {
        let p = try replyPayload(bytes)
        guard p[0] == DDCOpcode.capabilitiesReply.rawValue else { throw DDCPacketError.unexpectedOpcode(p[0]) }
        guard p.count >= 3 else { throw DDCPacketError.truncated }
        let got = UInt16(p[1]) << 8 | UInt16(p[2])
        guard got == offset else { throw DDCPacketError.offsetMismatch(expected: offset, actual: got) }
        return Array(p[3...])
    }

    /// Builds a display → host reply (fake monitors and tests).
    static func reply(_ payload: [UInt8]) -> [UInt8] {
        var bytes = [DDCAddress.displayWrite, 0x80 | UInt8(min(payload.count, maxPayload))] + payload.prefix(maxPayload)
        bytes.append(checksum(bytes, seed: DDCAddress.hostReply))
        return bytes
    }

    static func vcpReply(code: UInt8, maximum: UInt16, current: UInt16, type: UInt8 = 0, result: UInt8 = 0) -> [UInt8] {
        reply([DDCOpcode.getVCPReply.rawValue, result, code, type,
               UInt8(maximum >> 8), UInt8(maximum & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)])
    }

    /// VCP value for `fraction` of `maximum` (clamped to 0…maximum, rounded).
    static func value(forFraction fraction: Double, maximum: UInt16) -> UInt16 {
        guard fraction.isFinite else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        return UInt16((clamped * Double(maximum)).rounded())
    }
}

// MARK: - Capabilities string

/// Parsed MCCS capabilities string, e.g.
/// `(prot(monitor)type(lcd)model(P3225QE)cmds(01 02 03 07 0C E3 F3)vcp(02 04 10 12 60( 1B 0F 11) …)mccs_ver(2.1))`.
struct DDCCapabilities: Equatable, Hashable, Sendable {
    var raw: String
    var model: String?
    var mccsVersion: String?
    /// Advertised VCP codes → their allowed values (empty for continuous controls).
    var vcp: [UInt8: [UInt16]]

    func supports(_ code: VCPCode) -> Bool { vcp[code.rawValue] != nil }
    func values(for code: VCPCode) -> [UInt16] { vcp[code.rawValue] ?? [] }

    init(raw: String, model: String? = nil, mccsVersion: String? = nil, vcp: [UInt8: [UInt16]] = [:]) {
        self.raw = raw
        self.model = model
        self.mccsVersion = mccsVersion
        self.vcp = vcp
    }

    /// Parses a capabilities string; nil when it has no `vcp(…)` group.
    init?(parsing string: String) {
        let s = string.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
        guard let vcpBody = Self.group(named: "vcp", in: s) else { return nil }
        self.init(raw: s,
                  model: Self.group(named: "model", in: s),
                  mccsVersion: Self.group(named: "mccs_ver", in: s),
                  vcp: Self.parseVCPList(vcpBody))
    }

    /// Body of `name(…)` (balanced parentheses), searched case-insensitively.
    static func group(named name: String, in s: String) -> String? {
        let chars = Array(s)
        let lower = Array(s.lowercased())
        let key = Array(name.lowercased() + "(")
        guard key.count <= lower.count else { return nil }
        var i = 0
        while i + key.count <= lower.count {
            // the name must not be the tail of a longer word ("xvcp(")
            let boundary = i == 0 || !(lower[i - 1].isLetter || lower[i - 1] == "_")
            if boundary, Array(lower[i..<(i + key.count)]) == key {
                var depth = 1
                var j = i + key.count
                let start = j
                while j < chars.count {
                    if chars[j] == "(" { depth += 1 }
                    if chars[j] == ")" {
                        depth -= 1
                        if depth == 0 { return String(chars[start..<j]) }
                    }
                    j += 1
                }
                return String(chars[start...])   // unterminated: take the rest
            }
            i += 1
        }
        return nil
    }

    /// `02 04 14(05 08) 60( 1B 0F 11) EA(F800 F801)` → [0x02: [], 0x04: [], 0x14: [5, 8], …].
    /// Codes written without spaces ("1012") are split into byte pairs.
    static func parseVCPList(_ body: String) -> [UInt8: [UInt16]] {
        var result: [UInt8: [UInt16]] = [:]
        var lastCode: UInt8?
        var token = ""
        var inValues = false
        var values: [UInt16] = []

        func flushToken() {
            defer { token = "" }
            guard !token.isEmpty else { return }
            if inValues {
                values += valueTokens(token)
            } else {
                for code in codeTokens(token) {
                    result[code] = result[code] ?? []
                    lastCode = code
                }
            }
        }

        for ch in body {
            switch ch {
            case "(":
                flushToken()
                inValues = true
                values = []
            case ")":
                flushToken()
                if inValues, let code = lastCode { result[code] = (result[code] ?? []) + values }
                inValues = false
            case _ where ch.isHexDigit:
                token.append(ch)
            default:
                flushToken()
            }
        }
        flushToken()
        return result
    }

    private static func codeTokens(_ token: String) -> [UInt8] {
        let t = token.count % 2 == 1 ? "0" + token : token
        return stride(from: 0, to: t.count, by: 2).compactMap { i in
            let a = t.index(t.startIndex, offsetBy: i)
            return UInt8(t[a..<t.index(a, offsetBy: 2)], radix: 16)
        }
    }

    private static func valueTokens(_ token: String) -> [UInt16] {
        if token.count <= 4 { return UInt16(token, radix: 16).map { [$0] } ?? [] }
        return codeTokens(token).map(UInt16.init)
    }
}

// MARK: - Input sources

/// MCCS input source names (VCP 0x60, low byte of the current value).
enum DDCInputSource {
    static func name(_ value: UInt16) -> String {
        switch UInt8(value & 0xFF) {
        case 0x01: return "VGA 1"
        case 0x02: return "VGA 2"
        case 0x03: return "DVI 1"
        case 0x04: return "DVI 2"
        case 0x05: return "Composite 1"
        case 0x06: return "Composite 2"
        case 0x07: return "S-Video 1"
        case 0x08: return "S-Video 2"
        case 0x09: return "Tuner 1"
        case 0x0A: return "Tuner 2"
        case 0x0B: return "Tuner 3"
        case 0x0C: return "Component 1"
        case 0x0D: return "Component 2"
        case 0x0E: return "Component 3"
        case 0x0F: return "DisplayPort 1"
        case 0x10: return "DisplayPort 2"
        case 0x11: return "HDMI 1"
        case 0x12: return "HDMI 2"

        case 0x1B: return "USB-C"
        case let v: return String(format: "Input 0x%02X", v)
        }
    }

    /// Input source code from a VCP 0x60 reply: the low byte (some monitors, e.g. the DELL
    /// P3225QE, repeat it in the high byte: 0x1B1B).
    static func code(_ current: UInt16) -> UInt8 { UInt8(current & 0xFF) }
}

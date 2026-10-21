// DDC/CI transport for the Displays widget (2026-10-20).
//   - `DDCTransport`: one I2C write / read to a monitor's DDC/CI address.
//   - `IOAVServiceDDCTransport`: Apple Silicon. IOKit's IOAVService I2C functions

//     the public headers, so they are resolved with dlsym; nil when they are missing. Technique as
//     used by MonitorControl / BetterDisplay (MIT), written independently from the DDC/CI spec.
//   - `DDCChannel`: request → wait → reply with retries and the DDC/CI inter-message delays.
//     Blocking: call it only from DisplayControlService's serial I/O queue.
//   - `FakeDDCMonitor`: a simulated monitor (tests and DEBUG previews); the only "write" path that
//     was exercised while building this (docs/displays.md §4).
import Foundation
import IOKit

protocol DDCTransport: AnyObject {
    /// Sends one host message (`DDCPacket.message` bytes: length byte … checksum).
    func write(_ message: [UInt8]) throws
    /// Reads `count` reply bytes (from the 0x6E source byte on).
    func read(count: Int) throws -> [UInt8]
}

enum DDCTransportError: Error, Equatable, Sendable {
    case unavailable
    case ioError(Int32)
}

// MARK: - Channel

/// Not thread-safe: used only from DisplayControlService.ioQueue (hence `@unchecked Sendable`).
final class DDCChannel: @unchecked Sendable {
    struct Timing: Sendable {
        /// Wait between a request and reading its reply (DDC/CI: 40 ms; 50 ms worked on the DELL).
        var replyDelay: TimeInterval = 0.05
        /// Wait after a Set VCP before the next message (DDC/CI: 50 ms).
        var postWriteDelay: TimeInterval = 0.05
        /// Wait before a retry.
        var retryDelay: TimeInterval = 0.03
        var attempts: Int = 3

        static let immediate = Timing(replyDelay: 0, postWriteDelay: 0, retryDelay: 0, attempts: 3)
    }

    let transport: DDCTransport
    var timing: Timing
    /// Injected for tests (no real sleeping).
    var sleep: (TimeInterval) -> Void = { if $0 > 0 { Thread.sleep(forTimeInterval: $0) } }

    init(transport: DDCTransport, timing: Timing = Timing()) {
        self.transport = transport
        self.timing = timing
    }

    func readVCP(_ code: VCPCode) throws -> VCPReply {
        try readVCP(code.rawValue)
    }

    func readVCP(_ code: UInt8) throws -> VCPReply {
        var lastError: Error = DDCTransportError.unavailable
        for attempt in 0..<max(timing.attempts, 1) {
            if attempt > 0 { sleep(timing.retryDelay) }
            do {
                try transport.write(DDCPacket.getVCP(code))
                sleep(timing.replyDelay)
                return try DDCPacket.parseVCPReply(transport.read(count: DDCPacket.vcpReplyLength), expecting: code)
            } catch DDCPacketError.unsupportedCode(let c) {
                throw DDCPacketError.unsupportedCode(c)     // a definite answer: do not retry
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func writeVCP(_ code: VCPCode, value: UInt16) throws {
        try transport.write(DDCPacket.setVCP(code.rawValue, value: value))
        sleep(timing.postWriteDelay)
    }

    /// Reads the capabilities string fragment by fragment (at most `maxFragments`).
    func readCapabilities(maxFragments: Int = 64) throws -> DDCCapabilities? {
        var data: [UInt8] = []
        var offset: UInt16 = 0
        var fragments = 0
        while fragments < maxFragments {
            fragments += 1
            var chunk: [UInt8]?
            var lastError: Error = DDCTransportError.unavailable
            for attempt in 0..<max(timing.attempts, 1) where chunk == nil {
                if attempt > 0 { sleep(timing.retryDelay) }
                do {
                    try transport.write(DDCPacket.capabilitiesRequest(offset: offset))
                    sleep(timing.replyDelay)
                    chunk = try DDCPacket.parseCapabilitiesReply(transport.read(count: DDCPacket.capabilitiesReplyLength),
                                                                 expectingOffset: offset)
                } catch {
                    lastError = error
                }
            }
            guard let chunk else { throw lastError }
            if chunk.isEmpty { break }
            data += chunk
            offset &+= UInt16(chunk.count)
        }
        let text = String(decoding: data.filter { $0 != 0 }, as: UTF8.self)
        return DDCCapabilities(parsing: text)
    }
}

// MARK: - Apple Silicon IOAVService

/// The private-but-exported IOAVService I2C entry points of IOKit.framework.
enum IOAVServiceAPI {
    typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias I2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    struct Functions {
        var create: CreateWithService
        var read: I2C
        var write: I2C
    }

    static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let c = dlsym(handle, "IOAVServiceCreateWithService"),
              let r = dlsym(handle, "IOAVServiceReadI2C"),
              let w = dlsym(handle, "IOAVServiceWriteI2C") else { return nil }
        return Functions(create: unsafeBitCast(c, to: CreateWithService.self),
                         read: unsafeBitCast(r, to: I2C.self),
                         write: unsafeBitCast(w, to: I2C.self))
    }()

    static var isAvailable: Bool { functions != nil }
}

final class IOAVServiceDDCTransport: DDCTransport {
    private let service: CFTypeRef
    private let api: IOAVServiceAPI.Functions

    /// `proxy` is a DCPAVServiceProxy service whose "Location" is "External".
    init?(proxy: io_service_t) {
        guard let api = IOAVServiceAPI.functions,
              let service = api.create(kCFAllocatorDefault, proxy)?.takeRetainedValue() else { return nil }
        self.api = api
        self.service = service
    }

    func write(_ message: [UInt8]) throws {
        var bytes = message
        let r = bytes.withUnsafeMutableBytes { buf -> IOReturn in
            guard let base = buf.baseAddress else { return kIOReturnBadArgument }
            return api.write(service, UInt32(DDCAddress.display7Bit), UInt32(DDCAddress.host), base, UInt32(buf.count))
        }
        guard r == kIOReturnSuccess else { throw DDCTransportError.ioError(r) }
    }

    func read(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let r = bytes.withUnsafeMutableBytes { buf -> IOReturn in
            guard let base = buf.baseAddress else { return kIOReturnBadArgument }
            return api.read(service, UInt32(DDCAddress.display7Bit), UInt32(DDCAddress.host), base, UInt32(buf.count))
        }
        guard r == kIOReturnSuccess else { throw DDCTransportError.ioError(r) }
        return bytes
    }
}

// MARK: - Fake monitor

/// A simulated DDC/CI monitor: answers Get VCP and Capabilities requests from `values`, applies
/// Set VCP, and records every message. Rejects messages with a bad checksum like a real monitor
/// (no reply). Thread-safe (tests read it from the main actor while the service's queue writes).
final class FakeDDCMonitor: DDCTransport, @unchecked Sendable {
    struct Feature: Equatable, Sendable {
        var current: UInt16
        var maximum: UInt16
    }

    private let lock = NSLock()
    private var _values: [UInt8: Feature]
    private var _messages: [[UInt8]] = []
    private var pendingReply: [UInt8]?
    let capabilities: String
    /// The next `dropReplies` reads return an idle bus (all 0x00).
    var dropReplies = 0
    /// The next `corruptReplies` reads return a reply with a wrong checksum.
    var corruptReplies = 0
    /// When true, writes fail with an I/O error (unplugged monitor).
    var failWrites = false

    init(values: [UInt8: Feature] = [
            VCPCode.brightness.rawValue: Feature(current: 50, maximum: 100),
            VCPCode.contrast.rawValue: Feature(current: 75, maximum: 100),
            VCPCode.inputSource.rawValue: Feature(current: 0x0F, maximum: 0x12),
         ],
         capabilities: String = "(prot(monitor)type(lcd)model(FAKE)cmds(01 02 03 E3 F3)vcp(10 12 60(0F 11 1B))mccs_ver(2.1))") {
        self._values = values
        self.capabilities = capabilities
    }

    var values: [UInt8: Feature] { lock.withLock { _values } }
    var messages: [[UInt8]] { lock.withLock { _messages } }
    /// The Set VCP messages received, as (code, value).
    var setRequests: [(code: UInt8, value: UInt16)] {
        messages.compactMap { m in
            guard m.count == 6, m[1] == DDCOpcode.setVCP.rawValue else { return nil }
            return (m[2], UInt16(m[3]) << 8 | UInt16(m[4]))
        }
    }

    func write(_ message: [UInt8]) throws {
        try lock.withLock {
            if failWrites { throw DDCTransportError.ioError(kIOReturnNotResponding) }
            _messages.append(message)
            pendingReply = nil
            guard message.count >= 2,
                  DDCPacket.checksum(message.dropLast(), seed: DDCAddress.displayWrite ^ DDCAddress.host) == message.last
            else { return }                                    // bad checksum: ignored
            let payload = Array(message.dropFirst().dropLast())
            guard let op = payload.first else { return }
            switch op {
            case DDCOpcode.getVCP.rawValue where payload.count == 2:
                let code = payload[1]
                if let f = _values[code] {
                    pendingReply = DDCPacket.vcpReply(code: code, maximum: f.maximum, current: f.current)
                } else {
                    pendingReply = DDCPacket.vcpReply(code: code, maximum: 0, current: 0, result: 0x01)
                }
            case DDCOpcode.setVCP.rawValue where payload.count == 4:
                let code = payload[1]
                guard var f = _values[code] else { return }
                f.current = min(UInt16(payload[2]) << 8 | UInt16(payload[3]), f.maximum)
                _values[code] = f
            case DDCOpcode.capabilitiesRequest.rawValue where payload.count == 3:
                let offset = Int(payload[1]) << 8 | Int(payload[2])
                let bytes = Array(capabilities.utf8)
                let chunk = offset < bytes.count ? Array(bytes[offset..<min(offset + 32 - 3, bytes.count)]) : []
                pendingReply = DDCPacket.reply([DDCOpcode.capabilitiesReply.rawValue, payload[1], payload[2]] + chunk)
            default:
                break
            }
        }
    }

    func read(count: Int) throws -> [UInt8] {
        lock.withLock {
            var reply = pendingReply ?? []
            pendingReply = nil
            if dropReplies > 0 {
                dropReplies -= 1
                reply = []
            } else if corruptReplies > 0, !reply.isEmpty {
                corruptReplies -= 1
                reply[reply.count - 1] ^= 0xFF
            }
            reply += [UInt8](repeating: 0, count: max(count - reply.count, 0))
            return Array(reply.prefix(count))
        }
    }
}

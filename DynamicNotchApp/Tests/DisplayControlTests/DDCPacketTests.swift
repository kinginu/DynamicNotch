// DDC/CI packet encoding, checksums and reply parsing (Sources/DDCPacket.swift).
// Reference bytes: request checksums as printed by ddcutil (`6e 51 82 01 10 ac`, `6e 51 83 f3 00 00 4f`)
// and replies captured read-only from two DELL P3225QE monitors on this Mac (docs/displays.md §3).
import Foundation
import Testing
@testable import DynamicNotchApp

@Suite("DDC/CI packets")
struct DDCPacketTests {
    @Test func getVCPBrightnessMatchesReferenceBytes() {
        #expect(DDCPacket.getVCP(0x10) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func busMessageIncludesAddressesAndXorsToZero() throws {
        let bus = try DDCPacket.busMessage([0x01, 0x12])
        #expect(Array(bus.prefix(2)) == [0x6E, 0x51])
        #expect(bus.reduce(0, ^) == 0)   // checksum makes the XOR of the whole message 0
    }

    @Test func setVCPEncodesBigEndianValueAndChecksum() {
        #expect(DDCPacket.setVCP(0x10, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        let big = DDCPacket.setVCP(0x62, value: 0x1234)
        #expect(Array(big[0..<5]) == [0x84, 0x03, 0x62, 0x12, 0x34])
        #expect(big[5] == DDCPacket.checksum(big[0..<5], seed: 0x6E ^ 0x51))
    }

    @Test func capabilitiesRequestMatchesReferenceBytes() {
        #expect(DDCPacket.capabilitiesRequest(offset: 0) == [0x83, 0xF3, 0x00, 0x00, 0x4F])
        let at = DDCPacket.capabilitiesRequest(offset: 0x0120)
        #expect(Array(at[0..<4]) == [0x83, 0xF3, 0x01, 0x20])
        #expect(([0x6E, 0x51] + at).reduce(0, ^) == 0)
    }

    @Test(arguments: VCPCode.allCases)
    func everyRequestChecksumValidates(_ code: VCPCode) {
        for m in [DDCPacket.getVCP(code.rawValue), DDCPacket.setVCP(code.rawValue, value: 0xBEEF)] {
            #expect(m.first == 0x80 | UInt8(m.count - 2))
            #expect(([DDCAddress.displayWrite, DDCAddress.host] + m).reduce(0, ^) == 0)
            #expect(DDCPacket.opcode(ofMessage: m) == (m.count == 4 ? 0x01 : 0x03))
        }
    }

    @Test func messageRejectsOversizedPayload() {
        #expect(throws: DDCPacketError.payloadTooLong(33)) {
            try DDCPacket.message([UInt8](repeating: 0, count: 33))
        }
        #expect((try? DDCPacket.message([UInt8](repeating: 0, count: 32)))?.first == 0xA0)
    }

    @Test func parsesCapturedDellBrightnessReply() throws {
        let r = try DDCPacket.parseVCPReply([0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4A, 0x8A], expecting: 0x10)
        #expect(r == VCPReply(code: 0x10, type: 0, maximum: 100, current: 74))
        #expect(r.fraction == 0.74)
    }

    @Test func parsesCapturedDellInputReplyLowByte() throws {
        let r = try DDCPacket.parseVCPReply([0x6E, 0x88, 0x02, 0x00, 0x60, 0x00, 0x00, 0x0E, 0x1B, 0x1B, 0xDA], expecting: 0x60)
        #expect(r.current == 0x1B1B)
        #expect(DDCInputSource.code(r.current) == 0x1B)
        #expect(DDCInputSource.name(r.current) == "USB-C")
        #expect(DDCInputSource.name(0x11) == "HDMI 1")
        #expect(DDCInputSource.name(0x0F) == "DisplayPort 1")
        #expect(DDCInputSource.name(0x7F) == "Input 0x7F")
    }

    @Test func rejectsBadChecksum() {
        #expect(throws: DDCPacketError.badChecksum(expected: 0x8A, actual: 0x8B)) {
            try DDCPacket.parseVCPReply([0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4A, 0x8B], expecting: 0x10)
        }
    }

    @Test func rejectsIdleBusAndTruncatedReplies() {
        #expect(throws: DDCPacketError.badSource(0x00)) {
            try DDCPacket.parseVCPReply([UInt8](repeating: 0, count: 11), expecting: 0x10)
        }
        #expect(throws: DDCPacketError.truncated) {
            try DDCPacket.parseVCPReply([0x6E, 0x88, 0x02, 0x00, 0x10], expecting: 0x10)
        }
        #expect(throws: DDCPacketError.badLength(0x08)) {
            try DDCPacket.parseVCPReply([0x6E, 0x08, 0x02, 0x00, 0x10, 0, 0, 0, 0, 0, 0], expecting: 0x10)
        }
    }

    @Test func recognisesNullMessage() {
        // 6E 80 BE: "null message" (display busy / request not supported)
        #expect(throws: DDCPacketError.nullReply) {
            try DDCPacket.parseVCPReply([0x6E, 0x80, 0xBE], expecting: 0x10)
        }
    }

    @Test func reportsUnsupportedCodeAndCodeMismatch() {
        #expect(throws: DDCPacketError.unsupportedCode(0x62)) {
            try DDCPacket.parseVCPReply(DDCPacket.vcpReply(code: 0x62, maximum: 0, current: 0, result: 1), expecting: 0x62)
        }
        #expect(throws: DDCPacketError.codeMismatch(expected: 0x10, actual: 0x12)) {
            try DDCPacket.parseVCPReply(DDCPacket.vcpReply(code: 0x12, maximum: 100, current: 75), expecting: 0x10)
        }
        #expect(throws: DDCPacketError.unexpectedOpcode(0xE3)) {
            try DDCPacket.parseVCPReply(DDCPacket.reply([0xE3, 0, 0, 0x41]), expecting: 0x10)
        }
    }

    @Test func replyBuilderRoundTrips() throws {
        let bytes = DDCPacket.vcpReply(code: 0x10, maximum: 100, current: 74)
        #expect(bytes == [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4A, 0x8A])
        #expect(try DDCPacket.parseVCPReply(bytes, expecting: 0x10).current == 74)
        // trailing bus bytes after the checksum are ignored
        #expect(try DDCPacket.parseVCPReply(bytes + [0, 0, 0], expecting: 0x10).maximum == 100)
    }

    @Test func capabilitiesFragmentParsing() throws {
        let frag = DDCPacket.reply([0xE3, 0x00, 0x20] + Array("vcp(10 12)".utf8))
        #expect(try DDCPacket.parseCapabilitiesReply(frag, expectingOffset: 0x20) == Array("vcp(10 12)".utf8))
        #expect(throws: DDCPacketError.offsetMismatch(expected: 0, actual: 0x20)) {
            try DDCPacket.parseCapabilitiesReply(frag, expectingOffset: 0)
        }
        #expect(try DDCPacket.parseCapabilitiesReply(DDCPacket.reply([0xE3, 0x00, 0x40]), expectingOffset: 0x40).isEmpty)
    }

    @Test func valueForFractionClampsAndRounds() {
        #expect(DDCPacket.value(forFraction: 0.5, maximum: 100) == 50)
        #expect(DDCPacket.value(forFraction: 0.746, maximum: 100) == 75)
        #expect(DDCPacket.value(forFraction: -0.3, maximum: 100) == 0)
        #expect(DDCPacket.value(forFraction: 1.7, maximum: 100) == 100)
        #expect(DDCPacket.value(forFraction: .nan, maximum: 100) == 0)
        #expect(DDCPacket.value(forFraction: 1, maximum: 0xFFFF) == 0xFFFF)
        #expect(VCPReply(code: 0x10, type: 0, maximum: 0, current: 5).fraction == nil)
    }
}

@Suite("DDC/CI capabilities string")
struct DDCCapabilitiesTests {
    static let dell = "(prot(monitor)type(lcd)model(P3225QE)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 14(05 08 0B 0C) 16 18 1A 52 60( 1B 0F 11) 87 AA(00 01 04 02) AC AE B2 B6 C6 C8 C9 CA CC(02 03 04 06 09 0A 0D 0E) D6(01 04 05) DC(00 03 05) DF E0(03) E2(00 02 04 0E 12 14) EA(F800 F801) F1 F2 FE FD)mccs_ver(2.1)mswhql(1))"

    @Test func parsesCapturedDellString() throws {
        let c = try #require(DDCCapabilities(parsing: Self.dell))
        #expect(c.model == "P3225QE")
        #expect(c.mccsVersion == "2.1")
        #expect(c.supports(.brightness))
        #expect(c.supports(.contrast))
        #expect(c.supports(.inputSource))
        #expect(!c.supports(.audioVolume))          // no speakers, though VCP 0x62 answers 50
        #expect(c.values(for: .inputSource) == [0x1B, 0x0F, 0x11])
        #expect(c.vcp[0x14] == [0x05, 0x08, 0x0B, 0x0C])
        #expect(c.vcp[0xEA] == [0xF800, 0xF801])
        #expect(c.vcp[0xFD] == [])
    }

    @Test func handlesPackedCodesAndMissingVCPGroup() throws {
        let c = try #require(DDCCapabilities(parsing: "(type(lcd)vcp(1012 62 60(0F 11)))"))
        #expect(c.supports(.brightness) && c.supports(.contrast) && c.supports(.audioVolume))
        #expect(c.values(for: .inputSource) == [0x0F, 0x11])
        #expect(DDCCapabilities(parsing: "(prot(monitor)type(lcd))") == nil)
        // "xvcp(" is not the vcp group
        #expect(DDCCapabilities(parsing: "(xvcp(10))") == nil)
    }
}

@Suite("DDC/CI channel on a fake monitor")
struct DDCChannelTests {
    @Test func readsAndWritesThroughFakeMonitor() throws {
        let fake = FakeDDCMonitor()
        let ch = DDCChannel(transport: fake, timing: .immediate)
        #expect(try ch.readVCP(.brightness) == VCPReply(code: 0x10, type: 0, maximum: 100, current: 50))
        try ch.writeVCP(.brightness, value: 80)
        #expect(fake.values[0x10]?.current == 80)
        #expect(fake.setRequests.map(\.value) == [80])
        #expect(try ch.readVCP(.brightness).current == 80)
    }

    @Test func retriesAfterIdleBusAndBadChecksum() throws {
        let fake = FakeDDCMonitor()
        fake.dropReplies = 1
        fake.corruptReplies = 1
        let ch = DDCChannel(transport: fake, timing: .immediate)
        #expect(try ch.readVCP(.contrast).current == 75)
        #expect(fake.messages.count == 3)     // two failed attempts, one good
    }

    @Test func givesUpAfterAttemptsAndDoesNotRetryUnsupported() {
        let fake = FakeDDCMonitor()
        fake.dropReplies = 10
        let ch = DDCChannel(transport: fake, timing: .immediate)
        #expect(throws: (any Error).self) { try ch.readVCP(.brightness) }
        #expect(fake.messages.count == 3)

        let fake2 = FakeDDCMonitor()
        let ch2 = DDCChannel(transport: fake2, timing: .immediate)
        #expect(throws: DDCPacketError.unsupportedCode(0x62)) { try ch2.readVCP(.audioVolume) }
        #expect(fake2.messages.count == 1)
    }

    @Test func readsMultiFragmentCapabilities() throws {
        let fake = FakeDDCMonitor(capabilities: DDCCapabilitiesTests.dell)
        let ch = DDCChannel(transport: fake, timing: .immediate)
        let c = try #require(try ch.readCapabilities())
        #expect(c.raw == DDCCapabilitiesTests.dell)
        #expect(fake.messages.count > 5)      // 29 bytes per fragment
    }

    @Test func fakeIgnoresMessagesWithBadChecksum() throws {
        let fake = FakeDDCMonitor()
        var m = DDCPacket.setVCP(0x10, value: 99)
        m[m.count - 1] ^= 0x01
        try fake.write(m)
        #expect(fake.values[0x10]?.current == 50)
    }
}

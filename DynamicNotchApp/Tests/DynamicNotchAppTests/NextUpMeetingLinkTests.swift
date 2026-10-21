// NextUpMeetingLink.find (Sources/NextUpManager.swift): video-call link detection.
import Foundation
import Testing
@testable import DynamicNotchApp

@Suite("NextUp meeting links")
struct NextUpMeetingLinkTests {
    @Test("Recognised services", arguments: [
        ("https://us02web.zoom.us/j/123456789?pwd=abc", NextUpMeetingLink.Service.zoom),
        ("zoommtg://zoom.us/join?confno=123", .zoom),
        ("https://meet.google.com/abc-defg-hij", .meet),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting", .teams),
        ("https://acme.webex.com/meet/someone", .webex),
        ("https://facetime.apple.com/join#v=1&p=abc", .facetime),
    ])
    func services(_ link: String, _ service: NextUpMeetingLink.Service) throws {
        let found = try #require(NextUpMeetingLink.find(in: ["Join: \(link)"]))
        #expect(found.service == service)
        #expect(found.url.absoluteString == link)
    }

    @Test("Lookalike hosts are rejected", arguments: [
        "https://evilzoom.us/j/123",
        "https://zoom.us.evil.com/j/123",
        "https://notmeet.google.com.example/abc",
        "https://example.com/?u=meet.google",
    ])
    func lookalikes(_ text: String) {
        #expect(NextUpMeetingLink.find(in: [text]) == nil, "\(text)")
    }

    @Test("Trailing punctuation is trimmed")
    func trailingPunctuation() throws {
        let found = try #require(NextUpMeetingLink.find(in: ["Link: https://meet.google.com/abc-defg-hij."]))
        #expect(found.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test("Texts are searched in order; within a text the earliest link wins")
    func order() throws {
        let first = try #require(NextUpMeetingLink.find(in: [nil, "", "https://meet.google.com/aaa-bbbb-ccc",
                                                            "https://zoom.us/j/1"]))
        #expect(first.service == .meet)
        let earliest = try #require(NextUpMeetingLink.find(in: ["https://zoom.us/j/1 or https://meet.google.com/aaa-bbbb-ccc"]))
        #expect(earliest.service == .zoom)
    }

    @Test("No link")
    func none() {
        #expect(NextUpMeetingLink.find(in: []) == nil)
        #expect(NextUpMeetingLink.find(in: [nil, "Room 4B", "https://example.com"]) == nil)
    }
}

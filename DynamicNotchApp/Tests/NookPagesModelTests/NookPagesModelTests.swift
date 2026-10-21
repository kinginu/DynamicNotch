// F9: unit tests for NookPagesModel (Sources/Support/NookWidgetPagesModel.swift).
import Foundation
import Testing
import SwiftUI
@testable import DynamicNotchApp

private typealias M = NookPagesModel

/// Mirror of NookSettings' stored shape (synthesized Codable, optional page split).
private struct StoredNookSettings: Codable, Equatable {
    var widgets: [String] = []
    var separatorSpacing: Double = 24
    var widgetPages: [[String]]? = nil
}

@Suite("NookPages storage") struct NookPagesStorageTests {
    @Test func nilStoredIsOnePage() {
        #expect(M.pages(stored: nil, flat: ["a", "b"]) == [["a", "b"]])
        #expect(M.pages(stored: [], flat: ["a"]) == [["a"]])
        #expect(M.pages(stored: nil, flat: [String]()) == [[]])
    }
    @Test func removedWidgetsDisappearAddedGoLast() {
        let stored = [["a", "b"], ["c", "d"]]
        #expect(M.pages(stored: stored, flat: ["b", "c", "d"]) == [["b"], ["c", "d"]])
        #expect(M.pages(stored: stored, flat: ["a", "b", "c", "d", "e"]) == [["a", "b"], ["c", "d", "e"]])
        #expect(M.pages(stored: stored, flat: []) == [[], []])
    }
    @Test func duplicatesKeepFirst() {
        #expect(M.pages(stored: [["a", "b"], ["a", "c"]], flat: ["a", "b", "c"]) == [["a", "b"], ["c"]])
        #expect(M.storage(for: [["a"], ["a", "b"]]).flat == ["a", "b"])
    }
    @Test func singlePageStoresNil() {
        let s = M.storage(for: [["a", "b"]])
        #expect(s.flat == ["a", "b"]); #expect(s.pages == nil)
        let m = M.storage(for: [["a"], [], ["b"]])
        #expect(m.flat == ["a", "b"]); #expect(m.pages == [["a"], [], ["b"]])
    }
    @Test func roundTrip() {
        let pages = [["a"], ["b", "c"], []]
        let s = M.storage(for: pages)
        #expect(M.pages(stored: s.pages, flat: s.flat) == pages)
    }
    @Test func oldSettingsJSONDecodes() throws {
        // written before pages existed (sorted keys, like SettingsStore)
        let old = #"{"separatorSpacing":24,"widgets":["calendar","media"]}"#
        let s = try JSONDecoder().decode(StoredNookSettings.self, from: Data(old.utf8))
        #expect(s.widgetPages == nil)
        #expect(M.pages(stored: s.widgetPages, flat: s.widgets) == [["calendar", "media"]])
        // a single page encodes without the key
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        #expect(String(decoding: try enc.encode(s), as: UTF8.self) == old)
    }
    @Test func realNookSettingsMigrateAndRoundTrip() throws {
        let old = #"{"separatorSpacing":24,"widgets":["calendar","media","timer"]}"#
        var s = try JSONDecoder().decode(NookSettings.self, from: Data(old.utf8))
        #expect(s.pages == [[.calendar, .media, .timer]])
        s.pages = [[.timer], [.calendar, .media]]
        #expect(s.widgets == [.timer, .calendar, .media])
        let back = try JSONDecoder().decode(NookSettings.self, from: JSONEncoder().encode(s))
        #expect(back.pages == [[.timer], [.calendar, .media]])
        s.pages = [[.media, .timer, .calendar]]
        #expect(s.widgetPages == nil)
    }
}

@Suite("NookPages editing") struct NookPagesEditingTests {
    @Test func moveWithinPage() {
        #expect(M.move("a", toPage: 0, index: 2, in: [["a", "b", "c"]]) == [["b", "c", "a"]])
        #expect(M.move("c", toPage: 0, index: 0, in: [["a", "b", "c"]]) == [["c", "a", "b"]])
    }
    @Test func moveAcrossPages() {
        #expect(M.move("a", toPage: 1, index: 1, in: [["a", "b"], ["c"]]) == [["b"], ["c", "a"]])
        #expect(M.move("c", toPage: 0, index: 0, in: [["a", "b"], ["c"]]) == [["c", "a", "b"], []])
    }
    @Test func moveClampsAndAppendsPage() {
        #expect(M.move("a", toPage: 5, index: 9, in: [["a", "b"]]) == [["b"], ["a"]])
        #expect(M.move("a", toPage: -1, index: -3, in: [["b"], ["a"]]) == [["a", "b"], []])
        #expect(M.move("z", toPage: 0, index: 1, in: [["a", "b"]]) == [["a", "z", "b"]])
        #expect(M.move("z", toPage: 0, index: 0, in: [[String]]()) == [["z"]])
    }
    @Test func location() {
        #expect(M.location(of: "c", in: [["a"], ["b", "c"]])! == (1, 1))
        #expect(M.location(of: "x", in: [["a"]]) == nil)
    }
    @Test func addRemovePages() {
        #expect(M.addPage([["a"]]) == [["a"], []])
        #expect(M.removePage(1, from: [["a"], ["b"]]) == [["a", "b"]])
        #expect(M.removePage(0, from: [["a"], ["b"]]) == [["a", "b"]])
        #expect(M.removePage(1, from: [["a"], ["b"], ["c"]]) == [["a", "b"], ["c"]])
        #expect(M.removePage(0, from: [["a"]]) == [["a"]])
        #expect(M.removePage(4, from: [["a"], ["b"]]) == [["a"], ["b"]])
        #expect(M.removingEmptyPages([[], ["a"], []]) == [["a"]])
        #expect(M.removingEmptyPages([[String](), []]) == [[]])
    }
}

@Suite("NookPages settings rows") struct NookPagesSettingsRowsTests {
    @Test func singlePageHasNoHeaders() {
        #expect(M.rows([["a", "b"]]) == [.item("a"), .item("b")])
        #expect(M.pages(fromRows: [M.Row<String>.item("a")]) == [["a"]])
    }
    @Test func headersRoundTrip() {
        let pages = [["a"], [], ["b", "c"]]
        #expect(M.rows(pages) == [.page(0), .item("a"), .page(1), .page(2), .item("b"), .item("c")])
        #expect(M.pages(fromRows: M.rows(pages)) == pages)
    }
    @Test func onMoveSinglePageMatchesArrayMove() {
        var flat = ["a", "b", "c", "d"]
        let r = M.moveRows(in: [flat], fromOffsets: [0], toOffset: 3)
        flat.move(fromOffsets: [0], toOffset: 3)
        #expect(r == [flat])
    }
    @Test func onMoveAcrossPages() {
        // rows: P0 a b P1 c  — drag "a" (row 1) below "c" (end)
        #expect(M.moveRows(in: [["a", "b"], ["c"]], fromOffsets: [1], toOffset: 5) == [["b"], ["c", "a"]])
        // drag "c" (row 4) between P0 and a (offset 1)
        #expect(M.moveRows(in: [["a", "b"], ["c"]], fromOffsets: [4], toOffset: 1) == [["c", "a", "b"], []])
        // dropped above the first header → first page
        #expect(M.moveRows(in: [["a"], ["c"]], fromOffsets: [3], toOffset: 0) == [["c", "a"], []])
        // into an empty page (rows: P0 a P1 P2 b): "a" to just after P1
        #expect(M.moveRows(in: [["a"], [], ["b"]], fromOffsets: [1], toOffset: 3) == [[], ["a"], ["b"]])
    }
    @Test func headersAreNotMoved() {
        #expect(M.moveRows(in: [["a"], ["b"]], fromOffsets: [2], toOffset: 0) == [["a"], ["b"]])
    }
}

@Suite("NookPages layout") struct NookPagesLayoutTests {
    @Test func clamp() {
        #expect(M.clampPage(3, count: 2) == 1); #expect(M.clampPage(-1, count: 2) == 0); #expect(M.clampPage(0, count: 0) == 0)
    }
    @Test func pageOffset() {
        #expect(M.pageOffset(widths: [300, 400, 500], current: 0) == 0)
        #expect(M.pageOffset(widths: [300, 400, 500], current: 2) == 700)
    }
    @Test func origins() {
        #expect(M.cellOrigins(widths: [100, 200, 50], gap: 10) == [0, 110, 320])
    }
    @Test func insertionIndex() {
        // others: 100, 100 with gap 10; dragged 50 wide
        let o: [CGFloat] = [100, 100]
        #expect(M.insertionIndex(centerX: 0, draggedWidth: 50, others: o, gap: 10) == 0)
        #expect(M.insertionIndex(centerX: 25, draggedWidth: 50, others: o, gap: 10) == 0)
        #expect(M.insertionIndex(centerX: 135, draggedWidth: 50, others: o, gap: 10) == 1)
        #expect(M.insertionIndex(centerX: 1000, draggedWidth: 50, others: o, gap: 10) == 2)
        #expect(M.insertionIndex(centerX: -50, draggedWidth: 50, others: [], gap: 10) == 0)
    }
    @Test func insertionIsStableAroundCurrentSlot() {
        // dragging the first of [a(100), b(100)]: centre at a's own slot centre stays at 0;
        // past the midpoint between slot centres (50 and 160) it moves to 1
        let o: [CGFloat] = [100]
        #expect(M.insertionIndex(centerX: 50, draggedWidth: 100, others: o, gap: 10) == 0)
        #expect(M.insertionIndex(centerX: 104, draggedWidth: 100, others: o, gap: 10) == 0)
        #expect(M.insertionIndex(centerX: 106, draggedWidth: 100, others: o, gap: 10) == 1)
    }
    @Test func swipe() {
        #expect(M.swipeTarget(current: 0, count: 3, translation: -80, pageWidth: 400) == 1)
        #expect(M.swipeTarget(current: 1, count: 3, translation: 80, pageWidth: 400) == 0)
        #expect(M.swipeTarget(current: 1, count: 3, translation: -20, pageWidth: 400) == 1)
        #expect(M.swipeTarget(current: 1, count: 3, translation: -20, velocity: -1500, pageWidth: 400) == 2)
        #expect(M.swipeTarget(current: 2, count: 3, translation: -200, pageWidth: 400) == 2)
        #expect(M.swipeTarget(current: 0, count: 3, translation: 200, pageWidth: 400) == 0)
    }
    @Test func rubberBand() {
        #expect(M.rubberBand(-50, current: 0, count: 2) == -50)
        let b = M.rubberBand(100, current: 0, count: 2)
        #expect(b > 0 && b < 100)
        #expect(M.rubberBand(-100, current: 1, count: 2) == -b)
        #expect(abs(M.rubberBand(100_000, current: 0, count: 1)) < 160)
    }
}

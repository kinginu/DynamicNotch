import Testing
@testable import DynamicNotchApp

@Suite("NookPages pruning") struct NookPagesPruningTests {
    typealias M = NookPagesModel

    @Test func removesOnlyPagesTheDragEmptied() {
        let before = [["a"], ["b", "c"], [], ["d"]]
        let after = [[], ["b", "c", "a"], [], ["d"]]
        let r = M.pruningPagesEmptied(from: before, to: after, current: 1)
        #expect(r.pages == [["b", "c", "a"], [], ["d"]]); #expect(r.current == 0)
    }
    @Test func keepsCurrentPageOnTheMovedWidget() {
        // "d" carried from the last page to the empty page 1, which is current
        let r = M.pruningPagesEmptied(from: [["a"], [], ["d"]], to: [["a"], ["d"], []], current: 1)
        #expect(r.pages == [["a"], ["d"]]); #expect(r.current == 1)
    }
    @Test func lastWidgetLeavesOneEmptyPage() {
        let r = M.pruningPagesEmptied(from: [["a"]], to: [[]], current: 0)
        #expect(r.pages == [[]]); #expect(r.current == 0)
    }
    @Test func currentPageEmptiedFallsBack() {
        let r = M.pruningPagesEmptied(from: [["a"], ["b"]], to: [["a", "b"], []], current: 1)
        #expect(r.pages == [["a", "b"]]); #expect(r.current == 0)
    }
    @Test func noChange() {
        let r = M.pruningPagesEmptied(from: [["a", "b"]], to: [["b", "a"]], current: 0)
        #expect(r.pages == [["b", "a"]]); #expect(r.current == 0)
    }
}

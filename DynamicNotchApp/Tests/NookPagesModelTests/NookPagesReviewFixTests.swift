// Review fixes (2026-10-21) for widget pages: Settings add / remove through the pages, the grid's
// hand-made scrolling, which pages the grid mounts, and swipes whose end must always be handled.
import AppKit
import Foundation
import Testing
@testable import DynamicNotchApp

private typealias M = NookPagesModel

@Suite("NookPages settings add / remove") struct NookPagesAddRemoveTests {
    @Test func addingGoesToTheLastPageOnce() {
        #expect(M.adding("c", to: [["a"], ["b"]]) == [["a"], ["b", "c"]])
        #expect(M.adding("a", to: [["a"], ["b"]]) == [["a"], ["b"]])
        #expect(M.adding("a", to: [[String]]()) == [["a"]])
    }

    @Test func removingKeepsThePages() {
        #expect(M.removing("c", from: [["a", "b"], ["c"]]) == [["a", "b"], []])
        #expect(M.removing("x", from: [["a"]]) == [["a"]])
    }

    /// Finding: the detail pane's Remove left `widgetPages` stale, and Add put the widget back at
    /// its old page position instead of the last page.
    @Test func settingsRemoveThenAddUpdatesThePageSplit() {
        var s = NookSettings()
        s.pages = [[.calendar, .media], [.notes]]
        s.removeWidget(.notes)
        #expect(!s.widgets.contains(.notes))
        #expect(s.pages == [[.calendar, .media], []])
        s.removeWidget(.calendar)
        s.addWidget(.calendar)
        #expect(s.pages == [[.media], [.calendar]])
        #expect(s.widgets == [.media, .calendar])
    }
}

@Suite("Nook grid geometry scrolling") struct NookGridScrollGeometryTests {
    private func geometry(_ pages: [[NookWidget]], width: CGFloat, scroll: [Int: CGFloat] = [:]) -> NookGridGeometry {
        NookGridGeometry(pages: pages, current: 0, containerWidth: width, maxOpenWidth: width,
                         separatorSpacing: 24, scrollOffsets: scroll)
    }

    @Test func overflowingPageScrollIsClamped() {
        let g = geometry([[.calendar, .media]], width: 300, scroll: [0: 10_000])
        #expect(g.overflows(0))
        let max = g.rowWidth(0) - 300
        #expect(g.maxScroll(0) == max)
        #expect(g.scroll(0) == max)
        #expect(g.hiddenContent(0).trailing == 0)
        #expect(g.cellFrame(page: 0, index: 0).minX == NookWidgetLayout.horizontalPadding - max)
    }

    @Test func fittingPageNeverScrolls() {
        let g = geometry([[.calendar]], width: 600, scroll: [0: 40])
        #expect(!g.overflows(0))
        #expect(g.scroll(0) == 0)
        #expect(g.hiddenContent(0).leading == 0 && g.hiddenContent(0).trailing == 0)
    }
}

@Suite("Nook pager live pages") @MainActor struct NookPagerLivePagesTests {
    /// Finding: every page's widgets were mounted (an off-page Camera widget turned the camera on).
    @Test func onlyTheCurrentPageIsMountedAtRest() {
        let pager = NookWidgetPager()
        #expect(pager.livePages(count: 3) == [0])
        pager.currentPage = 1
        #expect(pager.livePages(count: 3) == [1])
        pager.swipeOffset = 12                    // a swipe shows the neighbours
        #expect(pager.livePages(count: 3) == [0, 1, 2])
        pager.swipeOffset = 0
        pager.currentPage = 5                     // clamped
        #expect(pager.livePages(count: 2) == [1])
    }

    @Test func aPageSlideKeepsBothPagesMounted() {
        let pager = NookWidgetPager()
        pager.show(page: 2, count: 3)
        #expect(pager.currentPage == 2)
        #expect(pager.livePages(count: 3) == [0, 2])
        #expect(pager.transitionFrom == 0)
    }
}

@Suite("Nook grid swipes", .serialized) @MainActor struct NookGridSwipeTests {
    private func withDraft(_ pages: [[NookWidget]], _ body: (NookGridInteraction) -> Void) {
        let pager = NookWidgetPager.shared
        let saved = (pager.currentPage, pager.draftPages, pager.dragged)
        pager.draftPages = pages
        pager.currentPage = 0
        let g = NookGridInteraction()
        g.containerWidth = 300
        g.maxOpenWidth = 300
        g.gridFrame = CGRect(x: 0, y: 0, width: 300, height: 218)
        body(g)
        pager.swipeOffset = 0
        pager.isSwiping = false
        (pager.currentPage, pager.draftPages, pager.dragged) = saved
    }

    private func sample(_ dx: CGFloat, _ phase: NSEvent.Phase) -> NookGridInteraction.ScrollSample {
        .init(dx: dx, dy: 0, precise: true, phase: phase)
    }

    /// Finding: an `.ended` arriving while a widget is dragged was dropped, leaving `isSwiping` on
    /// (the notch could not close).
    @Test func swipeEndIsHandledWhileDragging() {
        withDraft([[.calendar], [.notes]]) { g in
            let at = CGPoint(x: 150, y: 100)
            #expect(!g.scrollWheel(sample(0, .began), at: at))
            #expect(g.scrollWheel(sample(-40, .changed), at: at))
            #expect(NookWidgetPager.shared.isSwiping)
            NookWidgetPager.shared.dragged = .calendar
            #expect(g.scrollWheel(sample(0, .ended), at: at))
            #expect(!NookWidgetPager.shared.isSwiping)
        }
    }

    @Test func aNewGestureClosesAClaimedSwipe() {
        withDraft([[.calendar], [.notes]]) { g in
            let at = CGPoint(x: 150, y: 100)
            _ = g.scrollWheel(sample(0, .began), at: at)
            _ = g.scrollWheel(sample(-40, .changed), at: at)
            #expect(NookWidgetPager.shared.isSwiping)
            _ = g.scrollWheel(sample(0, .began), at: at)   // the previous end was lost
            #expect(!NookWidgetPager.shared.isSwiping)
        }
    }

    /// Overflowing pages scroll by hand (the strip lays every page's cells out itself).
    @Test func horizontalGestureScrollsAnOverflowingPage() {
        withDraft([[.calendar, .media]]) { g in
            let at = CGPoint(x: 150, y: 100)
            _ = g.scrollWheel(sample(0, .began), at: at)
            #expect(g.scrollWheel(sample(-40, .changed), at: at))
            #expect(g.scrollOffsets[0] == 40)
            #expect(g.scrollWheel(sample(-10_000, .changed), at: at))
            #expect(g.scrollOffsets[0] == g.geometry().maxScroll(0))
            #expect(g.scrollWheel(sample(0, .ended), at: at))
            #expect(!NookWidgetPager.shared.isSwiping)
        }
    }

    @Test func verticalGesturesReachTheWidgets() {
        withDraft([[.calendar, .media]]) { g in
            let at = CGPoint(x: 150, y: 100)
            _ = g.scrollWheel(sample(0, .began), at: at)
            #expect(!g.scrollWheel(.init(dx: 1, dy: -30, precise: true, phase: .changed), at: at))
            #expect(g.scrollOffsets[0] == nil)
        }
    }
}

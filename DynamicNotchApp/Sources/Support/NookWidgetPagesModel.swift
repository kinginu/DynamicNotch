// F9 (widget pages): the pure model behind Nook widget pages and drag-to-reorder.
//
// Kept free of app types (generic over the element, Foundation/CoreGraphics only) so it is easy to
// unit-test (Tests/NookPagesModelTests). The app binds it to `NookSettings` in NookWidgetPager.swift:
//   - `NookSettings.widgets` stays the flat list of every widget in the Nook (all pages, in page
//     order) — the many `widgets.contains(.x)` checks elsewhere keep working unchanged;
//   - `NookSettings.widgetPages` (optional, so settings written before pages existed still decode)
//     stores the page split; nil = one page = the behaviour before pages.
// Reconciliation is tolerant: widgets removed from the flat list disappear from their page,
// widgets added to the flat list (Settings "Add to Nook", DebugHooks `nookwidgets:`) land on the
// last page, duplicates keep their first position.
import CoreGraphics
import Foundation

enum NookPagesModel {
    // MARK: - Storage

    /// The pages to show for a stored page split and the flat widget list (always ≥ 1 page).
    static func pages<E: Hashable>(stored: [[E]]?, flat: [E]) -> [[E]] {
        guard let stored, !stored.isEmpty else { return [dedupe(flat)] }
        let present = Set(flat)
        var seen = Set<E>()
        var result = stored.map { page in page.filter { present.contains($0) && seen.insert($0).inserted } }
        let missing = flat.filter { seen.insert($0).inserted }
        result[result.count - 1].append(contentsOf: missing)
        return result
    }

    /// What to store for `pages`: the flat list, and the page split (nil for a single page, so a
    /// one-page Nook is stored exactly as before pages existed).
    static func storage<E: Hashable>(for pages: [[E]]) -> (flat: [E], pages: [[E]]?) {
        var seen = Set<E>()
        let deduped = pages.map { page in page.filter { seen.insert($0).inserted } }
        let flat = deduped.flatMap { $0 }
        return (flat, deduped.count > 1 ? deduped : nil)
    }

    static func dedupe<E: Hashable>(_ list: [E]) -> [E] {
        var seen = Set<E>()
        return list.filter { seen.insert($0).inserted }
    }

    // MARK: - Editing

    /// Page and index of an element.
    static func location<E: Hashable>(of element: E, in pages: [[E]]) -> (page: Int, index: Int)? {
        for (p, page) in pages.enumerated() {
            if let i = page.firstIndex(of: element) { return (p, i) }
        }
        return nil
    }

    /// Moves `element` to `index` of page `page` (both clamped; `page == pages.count` appends a

    static func move<E: Hashable>(_ element: E, toPage page: Int, index: Int, in pages: [[E]]) -> [[E]] {
        var result = pages.map { $0.filter { $0 != element } }
        if result.isEmpty { result = [[]] }
        let p = min(max(page, 0), result.count)
        if p == result.count { result.append([]) }
        let i = min(max(index, 0), result[p].count)
        result[p].insert(element, at: i)
        return result
    }

    /// Adds `element` at the end of the last page (unchanged if it is already on a page).
    static func adding<E: Hashable>(_ element: E, to pages: [[E]]) -> [[E]] {
        guard location(of: element, in: pages) == nil else { return pages }
        var result = pages.isEmpty ? [[]] : pages
        result[result.count - 1].append(element)
        return result
    }

    /// Removes `element` from whichever page holds it (pages stay, even when emptied).
    static func removing<E: Hashable>(_ element: E, from pages: [[E]]) -> [[E]] {
        pages.map { $0.filter { $0 != element } }
    }

    /// Appends an empty page.
    static func addPage<E>(_ pages: [[E]]) -> [[E]] {
        pages + [[]]
    }

    /// Removes page `index`; its widgets move to the end of the previous page (the first page's to
    /// the start of the next). The last remaining page cannot be removed.
    static func removePage<E>(_ index: Int, from pages: [[E]]) -> [[E]] {
        guard pages.count > 1, pages.indices.contains(index) else { return pages }
        var result = pages
        let moved = result.remove(at: index)
        if index == 0 {
            result[0].insert(contentsOf: moved, at: 0)
        } else {
            result[index - 1].append(contentsOf: moved)
        }
        return result
    }

    /// Removes empty pages (at least one page remains).
    static func removingEmptyPages<E>(_ pages: [[E]]) -> [[E]] {
        let kept = pages.filter { !$0.isEmpty }
        return kept.isEmpty ? [[]] : kept
    }

    /// After a drag from `before` to `after` (same page count: moves never add or remove pages),
    /// removes the pages the drag emptied (iOS-like; pages that were already empty stay as drop
    /// targets) and returns where the page `current` ended up.
    static func pruningPagesEmptied<E>(from before: [[E]], to after: [[E]], current: Int) -> (pages: [[E]], current: Int) {
        var pages = after
        var page = current
        for i in after.indices.reversed() where after[i].isEmpty && before.indices.contains(i) && !before[i].isEmpty {
            pages.remove(at: i)
            if page > i || (page == i && page == pages.count) { page -= 1 }
        }
        if pages.isEmpty { pages = [[]] }
        return (pages, clampPage(page, count: pages.count))
    }

    // MARK: - Settings list (one flat List with a header row per page, so rows can be dragged across pages)

    enum Row<E: Hashable>: Hashable {
        case page(Int)
        case item(E)

        var isItem: Bool {
            if case .item = self { return true }
            return false
        }
    }

    /// Rows for `pages`: a header row before every page when there is more than one page;
    /// a single page is just its items (exactly the list before pages existed).
    static func rows<E: Hashable>(_ pages: [[E]]) -> [Row<E>] {
        guard pages.count > 1 else { return (pages.first ?? []).map { .item($0) } }
        return pages.enumerated().flatMap { p, page in [Row<E>.page(p)] + page.map { .item($0) } }
    }

    /// Inverse of `rows`: every header starts a page; items above the first header belong to the
    /// first page (a row dropped above "Page 1").
    static func pages<E: Hashable>(fromRows rows: [Row<E>]) -> [[E]] {
        var result: [[E]] = []
        var leading: [E] = []
        for row in rows {
            switch row {
            case .page: result.append([])
            case .item(let e):
                if result.isEmpty { leading.append(e) } else { result[result.count - 1].append(e) }
            }
        }
        if result.isEmpty { result = [[]] }
        result[0].insert(contentsOf: leading, at: 0)
        return result
    }

    /// `List.onMove` on the rows of `pages`.
    static func moveRows<E: Hashable>(in pages: [[E]], fromOffsets: IndexSet, toOffset: Int) -> [[E]] {
        var r = Self.rows(pages)
        // header rows are not draggable (moveDisabled); ignore them if one slips through
        let movable = fromOffsets.filter { r.indices.contains($0) && r[$0].isItem }
        guard !movable.isEmpty else { return pages }
        // Array.move(fromOffsets:toOffset:) semantics (SwiftUI's) without importing SwiftUI
        let destination = min(max(toOffset, 0), r.count)
        let moved = movable.map { r[$0] }
        let before = movable.filter { $0 < destination }.count
        for i in movable.reversed() { r.remove(at: i) }
        r.insert(contentsOf: moved, at: destination - before)
        return Self.pages(fromRows: r)
    }

    // MARK: - Layout helpers

    /// Index of `current` clamped to the pages.
    static func clampPage(_ current: Int, count: Int) -> Int {
        min(max(current, 0), max(count - 1, 0))
    }

    /// Horizontal offset of page `current` in a strip of pages of `widths` laid out side by side.
    static func pageOffset(widths: [CGFloat], current: Int) -> CGFloat {
        widths.prefix(max(current, 0)).reduce(0, +)
    }

    /// Slot (0...others.count) for a dragged item whose centre is at `centerX`, measured from the
    /// leading edge of the first cell, among `others` (widths of the other items in order) with
    /// `gap` between cells. The slot whose centre (with the dragged item placed there) is nearest
    /// wins; it does not depend on where the dragged item is now, so the reflow cannot oscillate.
    static func insertionIndex(centerX: CGFloat, draggedWidth: CGFloat, others: [CGFloat], gap: CGFloat) -> Int {
        var best = 0
        var bestDistance = CGFloat.infinity
        var x: CGFloat = 0
        for slot in 0...others.count {
            let center = x + draggedWidth / 2
            let d = abs(centerX - center)
            if d < bestDistance { bestDistance = d; best = slot }
            if slot < others.count { x += others[slot] + gap }
        }
        return best
    }

    /// Leading x of each cell of a row of `widths` with `gap` between cells, starting at 0.
    static func cellOrigins(widths: [CGFloat], gap: CGFloat) -> [CGFloat] {
        var x: CGFloat = 0
        return widths.map { w in defer { x += w + gap }; return x }
    }

    /// Page after a horizontal swipe of `translation` (content follows the fingers: negative =
    /// towards the next page) with `velocity` (pt/s, same sign convention).
    static func swipeTarget(current: Int, count: Int, translation: CGFloat, velocity: CGFloat = 0,
                            pageWidth: CGFloat, threshold: CGFloat = 60) -> Int {
        let projected = translation + velocity * 0.15
        var target = current
        if translation <= -threshold || projected <= -pageWidth / 2 { target = current + 1 }
        if translation >= threshold || projected >= pageWidth / 2 { target = current - 1 }
        return clampPage(target, count: count)
    }

    /// Rubber-band a swipe translation past the first / last page (iOS-like resistance).
    static func rubberBand(_ translation: CGFloat, current: Int, count: Int, dimension: CGFloat = 160) -> CGFloat {
        let pastStart = current == 0 && translation > 0
        let pastEnd = current >= count - 1 && translation < 0
        guard pastStart || pastEnd else { return translation }
        let x = abs(translation)
        let banded = (1 - 1 / (x * 0.55 / dimension + 1)) * dimension
        return translation < 0 ? -banded : banded
    }
}

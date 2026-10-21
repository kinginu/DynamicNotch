// Rows-and-columns layout shared by the Shortcuts and Quick Apps widgets (moved here from
// ShortcutsWidgetView.swift in refactor R13, 2026-10-20; unchanged). Each item is a row — a 30 pt
// icon with its full name to the right — stacked into columns of up to 5 rows in the 202 pt cell;
// further rows start a new column and the widget grows by it (`NookRowColumnsPlan.cells`).
import SwiftUI
import AppKit

enum NookRowColumnsMetrics {
    /// Height of the Nook row's widget cell (WidgetGalleryDebug.rowHeight / MirrorWidgetLayout.rowHeight).
    static let cellHeight: CGFloat = 202
    static let rowHeight: CGFloat = 36
    static let rowSpacing: CGFloat = 1
    static let columnSpacing: CGFloat = 6
    static let iconSize: CGFloat = 30
    /// Corner radius of the visible 30 pt icon square (macOS squircle ≈ 22%); used by the shortcut tile.
    static let iconCornerRadius: CGFloat = 7
    /// App icons carry ~10% transparent padding per side (the visible squircle is ~80% of the canvas),
    /// so they are drawn at iconSize / 0.88 (measured: system icons render ≈ 32 px visible at 36 pt) inside the 30 pt slot to match the tile's visible size.
    static let appIconDrawSize: CGFloat = 34
    static let iconTextGap: CGFloat = 8
    /// Inset of a row's content from its hover highlight.
    static let rowInset: CGFloat = 4
    /// Width of a column with names (a single column = the former 150 pt widget minus padding).
    static let minColumnWidth: CGFloat = 134
    /// Longer names are truncated (tooltip shows them).
    static let maxColumnWidth: CGFloat = 220
    /// Width of an icon-only column (names hidden, or only the "+" row).
    static var iconColumnWidth: CGFloat { iconSize + 2 * rowInset }

    /// Rows per column in a cell of `cellHeight` (202 pt → 5).
    static func rowsPerColumn(cellHeight: CGFloat = cellHeight) -> Int {
        let available = cellHeight - 2 * NookWidgetMetrics.padding
        return max(1, Int((available + rowSpacing) / (rowHeight + rowSpacing)))
    }

    /// The label font (`.callout`, 12 pt on macOS) used to size the columns.
    static var labelFont: NSFont { NSFont.preferredFont(forTextStyle: .callout) }

    static func textWidth(_ string: String) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: labelFont]).width) + 2
    }
}

/// Which items go into which column, and how wide each column is. The last slot is the "+" row.
struct NookRowColumnsPlan: Equatable {
    struct Column: Equatable, Identifiable {
        let id: Int
        /// Indices into the items (may be empty for a column holding only the "+" row).
        let range: Range<Int>
        let hasAddRow: Bool
        let showsText: Bool
        let width: CGFloat
    }

    let columns: [Column]
    let rowsPerColumn: Int

    init(names: [String], showNames: Bool, addTitle: String,
         rowsPerColumn: Int = NookRowColumnsMetrics.rowsPerColumn()) {
        typealias M = NookRowColumnsMetrics
        self.rowsPerColumn = rowsPerColumn
        let slots = names.count + 1  // + the "+" row
        var columns: [Column] = []
        var start = 0
        while start < slots {
            let end = min(start + rowsPerColumn, slots)
            let range = start..<min(end, names.count)
            let hasAdd = end == slots
            let showsText = showNames && !range.isEmpty
            var width = M.iconColumnWidth
            if showsText {
                var text = range.map { M.textWidth(names[$0]) }.max() ?? 0
                if hasAdd { text = max(text, M.textWidth(addTitle)) }
                width = min(max(2 * M.rowInset + M.iconSize + M.iconTextGap + text, M.minColumnWidth), M.maxColumnWidth)
            }
            columns.append(Column(id: columns.count, range: range, hasAddRow: hasAdd, showsText: showsText,
                                  width: width.rounded(.up)))
            start = end
        }
        self.columns = columns
    }

    /// Widget width: padding + columns + gaps.
    var widgetWidth: CGFloat {
        2 * NookWidgetMetrics.padding
            + columns.map(\.width).reduce(0, +)
            + NookRowColumnsMetrics.columnSpacing * CGFloat(max(columns.count - 1, 0))
    }

    /// The same in 50 pt grid cells (NookWidgetLayout.cell).
    var cells: CGFloat { widgetWidth / 50 }
}

/// Lays the rows out in columns per `plan`. If the grid gives the widget less than
///   `plan.widgetWidth`, the columns scroll horizontally instead of being squeezed.
struct NookRowColumnsView<Item: Hashable, Row: View>: View {
    let items: [Item]
    let plan: NookRowColumnsPlan
    var addTitle: String
    var addHelp: Text
    var addAction: () -> Void
    @ViewBuilder var row: (Item, Bool) -> Row

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: NookRowColumnsMetrics.columnSpacing) {
                ForEach(plan.columns) { column in
                    VStack(alignment: .leading, spacing: NookRowColumnsMetrics.rowSpacing) {
                        ForEach(column.range.filter { $0 < items.count }, id: \.self) { index in
                            row(items[index], column.showsText)
                        }
                        if column.hasAddRow {
                            NookAddRow(title: addTitle, help: addHelp, showsText: column.showsText, action: addAction)
                        }
                    }
                    .frame(width: column.width, alignment: .topLeading)
                }
            }
            .padding(NookWidgetMetrics.padding)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// Row chrome: icon slot + single-line title, hover highlight (quaternary fill) and icon zoom.
struct NookIconRow<Icon: View, Title: View>: View {
    var hovering: Bool
    var showsText: Bool = true
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var title: () -> Title

    var body: some View {
        HStack(spacing: NookRowColumnsMetrics.iconTextGap) {
            icon()
                .frame(width: NookRowColumnsMetrics.iconSize, height: NookRowColumnsMetrics.iconSize)
                .scaleEffect(hovering ? 1.06 : 1)
            if showsText {
                title()
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, NookRowColumnsMetrics.rowInset)
        .frame(maxWidth: .infinity, minHeight: NookRowColumnsMetrics.rowHeight,
               maxHeight: NookRowColumnsMetrics.rowHeight, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous)
                .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear))
        }
        .contentShape(RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous))
    }
}

/// The "+" row at the end of the last column: a small glass "+" and a secondary label.
struct NookAddRow: View {
    var title: String
    var help: Text
    var showsText: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            NookIconRow(hovering: hovering, showsText: showsText) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .nookGlass(in: Circle(), interactive: true)
            } title: {
                Text(verbatim: title)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(ShrinkOnClick(minSize: 0.96))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(help)
        .accessibilityLabel(help)
    }
}

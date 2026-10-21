// Clipboard history widget (UI requirement (4), 2026-10-20). Apple-style per
// Support/NookWidgetChrome.swift: a header (title + Clear), then the recent items newest first —
// type icon (or image thumbnail), one or two lines of text, relative time. Clicking a row copies
// it again (checkmark feedback); hovering a row shows a delete button.
import SwiftUI
import AppKit

struct ClipboardWidgetView: View {
    @State private var manager = ClipboardHistoryManager.shared
    @StoredSetting(.clipboardWidgetSettings) private var settings
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            NookWidgetHeader("Clipboard", systemImage: settings.isRecording ? "doc.on.clipboard" : "pause.circle") {
                if !manager.items.isEmpty {
                    NookClearHistoryButton(help: String(localized: "Clear clipboard history")) { manager.clear() }
                }
            }
            if manager.items.isEmpty {
                NookWidgetEmptyState(
                    systemImage: "doc.on.clipboard",
                    title: String(localized: "No Clipboard History"),
                    message: settings.isRecording
                        ? String(localized: "Copied text appears here.")
                        : String(localized: "Recording is paused.")
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.items) { item in
                            ClipboardRowView(
                                item: item,
                                thumbnail: item.kind == .image ? manager.thumbnail(for: item) : nil,
                                copied: copiedID == item.id,
                                onCopy: { copy(item) },
                                onDelete: { withAnimation(.easeInOut(duration: 0.2)) { manager.delete(item) } }
                            )
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .nookWidgetFrame()
        .onAppear { manager.start() }
        .nookWidgetGalleryHook()
    }

    private func copy(_ item: ClipboardItem) {
        guard manager.copy(item) else { NSSound.beep(); return }
        withAnimation(.easeInOut(duration: 0.15)) { copiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == item.id { withAnimation { copiedID = nil } }
        }
    }
}

private struct ClipboardRowView: View {
    let item: ClipboardItem
    let thumbnail: NSImage?
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            leading
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(item.kind == .text ? 2 : 1)
                    .truncationMode(.tail)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(relativeTime(now: context.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if copied {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(Text("Copied"))
            } else if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "Delete"))
                .accessibilityLabel(Text("Delete"))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .nookListRowBackground(highlighted: hovering || copied, separatorInset: 34)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { hovering = $0 }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Copies this item again"))
        .accessibilityAction(named: Text("Delete"), onDelete)
    }

    @ViewBuilder
    private var leading: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: item.symbolName)
                .font(.footnote)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quinary))
        }
    }

    private func relativeTime(now: Date) -> String {
        if now.timeIntervalSince(item.date) < 60 { return String(localized: "Just now") }
        return item.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    private var helpText: String {
        if let app = item.sourceAppName {
            return String(localized: "Click to copy · from \(app)")
        }
        return String(localized: "Click to copy")
    }
}

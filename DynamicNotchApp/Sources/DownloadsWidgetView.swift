// F8: Downloads widget (2026-10-20). The newest items of the watched folder (default
// ~/Downloads) like Safari's / Finder's downloads stack: Quick Look thumbnail, name, size and age;
// downloads in progress first with a progress bar (determinate when the browser publishes
// progress or Safari's bundle records the total, else size growth + rate). Click opens; hover shows
// Quick Look and Show in Finder; the context menu adds Add to Tray and Copy; rows drag out as files
// (NSItemProvider). The … menu has Open Folder and Clear Old Items… (an inline confirmation, then
// NSWorkspace.recycle). Apple-style per Support/NookWidgetChrome.swift and WidgetUI/; 5 grid cells (250 pt).
// Data: DownloadsWatcher. The closed-notch progress indicator is `DownloadsClosedNotchIndicator`.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DownloadsWidgetLayout {
    static let cells: CGFloat = 5
    static let rowHeight: CGFloat = 32
    static let progressRowHeight: CGFloat = 40
    static let thumbnailSide: CGFloat = 26
}

enum DownloadsFormat {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func age(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return String(localized: "Just now") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.dateTimeStyle = .named
        return f.localizedString(for: date, relativeTo: now)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        String(format: String(localized: "%@/s"), bytes(Int64(bytesPerSecond)))
    }

    /// "45% · 1.2 MB/s", "12.3 MB of 30 MB", "12.3 MB · Stopped".
    static func progressDetail(_ p: DownloadProgress) -> String {
        var parts: [String] = []
        if let total = p.totalBytes, total > 0 {
            parts.append(String(format: String(localized: "%@ of %@"), bytes(p.bytes), bytes(total)))
        } else if let f = p.fraction {
            parts.append(percent(f))
        } else {
            parts.append(bytes(p.bytes))
        }
        if p.isStalled {
            parts.append(String(localized: "Stopped"))
        } else if let r = p.bytesPerSecond, r > 0 {
            parts.append(rate(r))
        }
        return parts.joined(separator: " · ")
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// DEBUG previews: fixed items / progress / status instead of the watcher's.
struct DownloadsPreviewState {
    var items: [DownloadItem]
    var progress: [String: DownloadProgress] = [:]
    var status: DownloadsWatcher.FolderStatus = .ok
    var clearPlan: DownloadsWatcher.ClearPlan? = nil
    var now = Date()
}

struct DownloadsWidgetView: View {
    @State private var watcher = DownloadsWatcher.shared
    @StoredSetting(.downloadsWidgetSettings) private var settings
    var preview: DownloadsPreviewState? = nil
    /// Report appear / disappear to the watcher (false for offscreen DEBUG renders, which never
    /// get `onDisappear`).
    var tracksVisibility = true

    private var items: [DownloadItem] { preview?.items ?? watcher.items }
    private var status: DownloadsWatcher.FolderStatus { preview?.status ?? watcher.status }
    private var clearPlan: DownloadsWatcher.ClearPlan? { preview != nil ? preview?.clearPlan : watcher.clearPlan }

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            header
            if let plan = clearPlan {
                DownloadsClearConfirmation(plan: plan,
                                           cancel: { watcher.cancelClear() },
                                           confirm: { watcher.confirmClear() })
            } else if preview == nil && watcher.isPreparingClear {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
            if preview == nil, let message = watcher.clearMessage {
                NookWidgetFootnote(text: message, lineLimit: 2, minimumScaleFactor: 0.8)
                    .onTapGesture { watcher.dismissClearMessage() }
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(5))
                        if watcher.clearMessage == message { watcher.dismissClearMessage() }
                    }
            }
        }
        .nookWidgetFrame()
        .onAppear {
            if preview == nil && tracksVisibility { watcher.setVisible(true) }
        }
        .onDisappear {
            if preview == nil && tracksVisibility {
                watcher.setVisible(false)
                watcher.cancelClear()
            }
        }
    }

    // MARK: header

    private var header: some View {
        NookWidgetHeader("Downloads", systemImage: "arrow.down.circle") {
            Menu {
                Button("Open Folder", systemImage: "folder") { watcher.openFolder() }
                Button("Clear Old Items…", systemImage: "trash") { watcher.prepareClear() }
                    .disabled(status != .ok || watcher.isClearing)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help(String(localized: "More"))
            .accessibilityLabel(Text("More"))
        }
        .frame(height: 18)
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        switch status {
        case .denied:
            NookWidgetEmptyState(
                systemImage: "lock",
                title: String(localized: "No access to the folder"),
                message: String(localized: "Allow DynamicNotch in System Settings ▸ Privacy & Security ▸ Files and Folders."),
                actionTitle: String(localized: "Open System Settings"),
                action: { DownloadsWatcher.openFilesAndFoldersPrivacy() }
            )
        case .missing, .notFolder:
            NookWidgetEmptyState(
                systemImage: "questionmark.folder",
                title: String(localized: "Folder not found"),
                message: settings.folderURL.path
            )
        case .unknown where items.isEmpty:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            if items.isEmpty {
                NookWidgetEmptyState(
                    systemImage: "arrow.down.circle",
                    title: String(localized: "No downloads"),
                    message: String(localized: "Files you download appear here.")
                )
            } else {
                list
            }
        }
    }

    private var list: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = preview?.now ?? context.date
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        DownloadRow(item: item,
                                    progress: preview?.progress[item.id] ?? watcher.progress[item.id],
                                    now: now,
                                    isPreview: preview != nil)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Row

struct DownloadRow: View {
    let item: DownloadItem
    let progress: DownloadProgress?
    let now: Date
    var isPreview = false

    @State private var hovering = false
    private var watcher: DownloadsWatcher { .shared }
    private var inProgress: Bool { progress != nil }

    var body: some View {
        HStack(spacing: 8) {
            DownloadThumbnail(item: item, inProgress: inProgress, isPreview: isPreview)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let progress {
                    DownloadProgressBar(fraction: progress.fraction, isStalled: progress.isStalled)
                    Text(verbatim: DownloadsFormat.progressDetail(progress))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(verbatim: detail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if hovering && !isPreview {
                HStack(spacing: 2) {
                    rowButton("eye", label: Text("Quick Look")) { watcher.quickLook(item) }
                    rowButton("magnifyingglass", label: Text("Show in Finder")) { watcher.reveal(item) }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: inProgress ? DownloadsWidgetLayout.progressRowHeight : DownloadsWidgetLayout.rowHeight)
        .contentShape(Rectangle())
        .nookListRowBackground(highlighted: hovering)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(count: 1) {
            // a download still being written opens in Finder instead
            if inProgress { watcher.reveal(item) } else { watcher.open(item) }
        }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app") { watcher.open(item) }
                .disabled(inProgress)
            Button("Quick Look", systemImage: "eye") { watcher.quickLook(item) }
            Button("Show in Finder", systemImage: "folder") { watcher.reveal(item) }
            Divider()
            Button("Add to Tray", systemImage: "tray.and.arrow.down") { watcher.addToTray(item) }
                .disabled(inProgress)
            Button("Copy", systemImage: "doc.on.doc") { watcher.copyToPasteboard(item) }
        }
        .help(Text(verbatim: item.url.path))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text(verbatim: progress.map(DownloadsFormat.progressDetail) ?? detail))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Quick Look")) { watcher.quickLook(item) }
        .accessibilityAction(named: Text("Show in Finder")) { watcher.reveal(item) }
    }

    private var detail: String {
        var parts: [String] = []
        if let size = item.size { parts.append(DownloadsFormat.bytes(size)) }
        parts.append(DownloadsFormat.age(item.added, now: now))
        return parts.joined(separator: " · ")
    }

    private func rowButton(_ systemImage: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Thin capsule progress bar; indeterminate = a sliding segment, stopped = grey.
struct DownloadProgressBar: View {
    var fraction: Double?
    var isStalled: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let fraction {
                    Capsule()
                        .fill(isStalled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                        .frame(width: max(geo.size.width * fraction, 3))
                        .animation(.smooth(duration: 0.3), value: fraction)
                } else if isStalled {
                    Capsule().fill(.secondary).frame(width: geo.size.width * 0.25)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        let w = geo.size.width * 0.3
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: w)
                            .offset(x: (geo.size.width + w) * t - w)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// Quick Look thumbnail (Support/Ext-C2.swift's cache), the Finder icon while it loads; downloads
/// in progress show the icon of the final file type with a download badge.
struct DownloadThumbnail: View {
    let item: DownloadItem
    let inProgress: Bool
    var isPreview = false

    @State private var thumbnail: NSImage?

    private var side: CGFloat { DownloadsWidgetLayout.thumbnailSide }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: thumbnail ?? fallbackIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: thumbnail != nil ? 4 : 0, style: .continuous))
            if inProgress {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: side, height: side)
        .task(id: "\(item.id)|\(item.modified.timeIntervalSince1970)|\(inProgress)") {
            guard !inProgress, !isPreview || FileManager.default.fileExists(atPath: item.url.path) else {
                thumbnail = nil
                return
            }
            thumbnail = await TrayThumbnails.thumbnail(for: item.url, side: side)
        }
        .accessibilityHidden(true)
    }

    private var fallbackIcon: NSImage {
        if inProgress || !FileManager.default.fileExists(atPath: item.url.path) {
            let type = UTType(filenameExtension: item.finalExtension) ?? (item.isDirectory ? .folder : .data)
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(forFile: item.url.path)
    }
}

// MARK: - Clear Old confirmation

struct DownloadsClearConfirmation: View {
    let plan: DownloadsWatcher.ClearPlan
    var cancel: () -> Void
    var confirm: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: plan.urls.isEmpty ? "checkmark.circle" : "trash")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            if plan.urls.isEmpty {
                Text(String(format: String(localized: "No items older than %lld days."), plan.days))
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                Button("OK", action: cancel)
                    .controlSize(.small)
                    .nookButtonStyle()
            } else {
                Text(String(format: String(localized: "Move %lld items to the Trash?"), plan.urls.count))
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(String(format: String(localized: "Added more than %lld days ago · %@. You can put them back from the Trash."),
                            plan.days, DownloadsFormat.bytes(plan.bytes)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 8) {
                    Button("Cancel", action: cancel)
                        .keyboardShortcut(.cancelAction)
                        .nookButtonStyle()
                    Button("Move to Trash", role: .destructive, action: confirm)
                        .nookButtonStyle(prominent: true)
                        .tint(.red)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Closed-notch indicator

/// F8: progress ring | percentage (or bytes) beside the camera housing while a download is in
/// progress and no other live activity or the Capture recording indicator holds the closed notch.
/// Hooked in with `// F8:` lines in NotchView (footprint / render) and
/// LiveActivities/ClosedNotchActivitiesView.swift (side width / row), like CaptureClosedNotchIndicator.
struct DownloadsClosedNotchIndicator: View {
    let notchSize: CGSize
    /// DEBUG previews: a fixed progress instead of the watcher's.
    var preview: DownloadProgress? = nil

    @MainActor private static var allowed: Bool {
        DownloadsWatcher.shared.wantsClosedNotchIndicator && LiveActivityCenter.shared.liveSettings.enabled
            && !CaptureClosedNotchIndicator.isShown
    }

    /// Extra width on each side of the hardware notch (0 unless a download runs with no other activity).
    @MainActor static func extraSideWidth(activity: LiveActivity?, notchHeight: CGFloat) -> CGFloat {
        guard activity == nil, allowed else { return 0 }
        return sideWidth(notchHeight: notchHeight)
    }

    static func sideWidth(notchHeight: CGFloat) -> CGFloat { max(notchHeight, 24) + 20 }

    /// True when the closed notch must be widened for the indicator.
    @MainActor static var isShown: Bool { allowed }

    var body: some View {
        let side = Self.sideWidth(notchHeight: notchSize.height)
        if let p = preview ?? (Self.allowed ? DownloadsWatcher.shared.combinedProgress : nil) {
            HStack(spacing: 0) {
                DownloadsRing(fraction: p.fraction, diameter: 15)
                    .padding(.leading, ClosedNotchActivityLayout.outerInset)
                    .frame(width: side, height: notchSize.height, alignment: .leading)
                Color.clear
                    .frame(width: notchSize.width, height: notchSize.height)
                Text(verbatim: p.fraction.map(DownloadsFormat.percent) ?? DownloadsFormat.bytes(p.bytes))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .padding(.trailing, ClosedNotchActivityLayout.outerInset)
                    .frame(width: side, height: notchSize.height, alignment: .trailing)
            }
            .frame(height: notchSize.height)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Downloading"))
            .accessibilityValue(Text(verbatim: DownloadsFormat.progressDetail(p)))
        }
    }
}

/// Download ring: track + progress arc around an arrow (indeterminate = a rotating arc).
struct DownloadsRing: View {
    var fraction: Double?
    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(fraction, 0.02))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.3), value: fraction)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(angle - 90))
                }
            }
            Image(systemName: "arrow.down")
                .font(.system(size: diameter * 0.5, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
    }
}

extension DownloadsWatcher {
    static func openFilesAndFoldersPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}

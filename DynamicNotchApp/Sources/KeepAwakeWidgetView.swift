// Keep Awake widget (2026-10-20). Apple-style per Support/NookWidgetChrome.swift: header
// (title + on/off switch), a ring around a cup that empties as the countdown runs, the remaining
// time and what is kept awake, and duration chips (15m / 1h / 2h / ∞) that start or restart a
// session. KeepAwakeManager holds the IOKit assertion.
import SwiftUI
import AppKit

/// Preview-only state (DEBUG snapshots): drawn without touching the manager or the assertion.
struct KeepAwakePreviewState {
    var session: KeepAwakeManager.Session?
    var allowDisplaySleep: Bool
    var now: Date
}

enum KeepAwakeStyle {
    /// Warm "coffee" amber used for the ring, the active chip and the live activity.
    static let tint = Color(red: 0.98, green: 0.69, blue: 0.27)
}

struct KeepAwakeWidgetView: View {
    var preview: KeepAwakePreviewState? = nil

    @State private var manager = KeepAwakeManager.shared
    @StoredSetting(.keepAwakeWidgetSettings) private var settings

    private var session: KeepAwakeManager.Session? { preview != nil ? preview?.session : manager.session }
    private var allowDisplaySleep: Bool { preview?.allowDisplaySleep ?? settings.allowDisplaySleep }

    var body: some View {
        VStack(spacing: NookWidgetMetrics.stackSpacing) {
            header
            if let preview {
                content(now: preview.now)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(now: context.date)
                }
            }
            chips
        }
        .nookWidgetFrame()
        .onAppear { if preview == nil { manager.start() } }
        .nookWidgetGalleryHook()
    }

    private var header: some View {
        NookWidgetHeader("Keep Awake", systemImage: session != nil ? "cup.and.saucer.fill" : "cup.and.saucer") {
            Toggle(isOn: Binding(
                get: { session != nil },
                set: { on in
                    guard preview == nil else { return }
                    if on { manager.activate(settings.lastDuration) } else { manager.deactivate() }
                }
            )) { Text("Keep Awake") }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(KeepAwakeStyle.tint)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let remaining = session?.endDate.map { max(0, $0.timeIntervalSince(now)) }
        let total = session?.duration.seconds ?? 1
        let progress: Double = session == nil ? 0 : (remaining.map { $0 / max(total, 1) } ?? 1)
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(KeepAwakeStyle.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.9), value: progress)
                Image(systemName: session != nil ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 22, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(session != nil ? AnyShapeStyle(KeepAwakeStyle.tint) : AnyShapeStyle(.tertiary))
                    .symbolEffect(.bounce, value: session != nil)
            }
            .frame(width: 62, height: 62)
            .padding(.top, 2)

            Group {
                if session == nil {
                    Text("Off")
                } else if let remaining {
                    Text(verbatim: KeepAwakeFormat.countdown(remaining))
                        .contentTransition(.numericText(countsDown: true))
                } else {
                    Text(verbatim: "∞")
                }
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(session != nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .lineLimit(1)

            Text(statusLine(remaining: remaining))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func statusLine(remaining: TimeInterval?) -> String {
        guard let session else {
            // the last start failed (IOKit refused the assertion): say so here, not only in Settings
            if preview == nil, manager.lastError != nil { return String(localized: "Could not keep the Mac awake") }
            return String(localized: "Mac sleeps normally")
        }
        let what = allowDisplaySleep ? String(localized: "Mac awake") : String(localized: "Mac and display awake")
        if let end = session.endDate {
            let time = end.formatted(date: .omitted, time: .shortened)
            return String(localized: "\(what) until \(time)")
        }
        return String(localized: "\(what) until turned off")
    }

    private var chips: some View {
        HStack(spacing: 4) {
            ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                NookChip(isSelected: session?.duration == duration, horizontalPadding: 4) {
                    guard preview == nil else { return }
                    manager.activate(duration)
                } label: {
                    Text(verbatim: duration.chipLabel)
                }
                .tint(KeepAwakeStyle.tint)
                .help(duration.title)
                .accessibilityLabel(Text(duration.title))
            }
        }
    }
}

// MARK: - Closed-notch live activity

/// One side of the `.keepAwake` live activity: leading = cup, trailing = remaining time ("∞" until
/// turned off). ClosedNotchActivityLayout uses `sideWidth`.
struct KeepAwakeLiveActivityView: View {
    var side: LiveActivityView.ActivitySide
    var preview: KeepAwakePreviewState? = nil

    private var session: KeepAwakeManager.Session? {
        preview != nil ? preview?.session : KeepAwakeManager.shared.session
    }

    var body: some View {
        switch side {
        case .leading:
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KeepAwakeStyle.tint)
                .accessibilityLabel(Text("Keep Awake"))
        case .trailing:
            if let end = session?.endDate {
                if let preview {
                    label(end.timeIntervalSince(preview.now))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        label(end.timeIntervalSince(context.date))
                    }
                }
            } else {
                Image(systemName: "infinity")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KeepAwakeStyle.tint)
                    .accessibilityLabel(Text("Until turned off"))
            }
        }
    }

    private func label(_ remaining: TimeInterval) -> some View {
        Text(verbatim: KeepAwakeFormat.countdown(max(0, remaining)))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(KeepAwakeStyle.tint)
            .contentTransition(.numericText(countsDown: true))
            .lineLimit(1)
            .fixedSize()
    }

    /// Width of each side (both sides use the same width so the camera housing stays centred):
    /// room for "1:59:59" while ≥ 1 h remains, "59:59" below.
    /// Called from ClosedNotchActivityLayout (main thread: view layout).
    nonisolated static func sideWidth(notchHeight: CGFloat) -> CGFloat {
        let h = max(notchHeight, 24)
        let left = MainActor.assumeIsolated { KeepAwakeManager.shared.remaining() }
        guard let remaining = left else { return h + 8 }
        return remaining >= 3600 ? 66 : 54
    }
}

// Next Up widget (2026-10-20, NookWidget.nextUp): the next 1–3 calendar events with a live
// countdown ("in 12 min", "now · 23 min left"), title, calendar colour dot, time range, location,
// and a Join button when the event carries a Zoom / Meet / Teams / Webex / FaceTime link (opened
// in the default browser). While the closed-notch activity is up, the header shows a button that
// dismisses it. Data: NextUpManager (EventKit via CalendarManager's access).
import SwiftUI
import EventKit

struct NextUpWidgetView: View {
    /// DEBUG previews: fixed rows instead of the manager's (nil = live data).
    var previewItems: [NextUpItem]? = nil
    var previewNow: Date? = nil
    var previewActivity = false

    private var manager: NextUpManager { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            if previewItems == nil && !manager.hasAccess {
                accessView
            } else {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let now = previewNow ?? context.date
                    let rows = previewItems.map { Array($0.prefix(3)) } ?? manager.visibleItems(at: now)
                    header(count: rows.count)
                    if rows.isEmpty {
                        NookWidgetEmptyState(
                            systemImage: "calendar.badge.checkmark",
                            title: String(localized: "Nothing coming up"),
                            message: String(localized: "No events in the next \(manager.settings.lookaheadHours) h")
                        )
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                                    NextUpRowView(item: item, now: now, isFirst: index == 0)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
        .nookWidgetFrame()
        .nookWidgetGalleryHook()
        .onAppear {
            guard previewItems == nil else { return }
            CalendarManager.shared.refreshAuthorizationStatus()
            manager.start()
            manager.refresh()
        }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("Next Up")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if previewActivity || manager.activityItem != nil {
                NookRoundIconButton(systemImage: "bell.slash", label: Text("Dismiss notch reminder"), diameter: 20) {
                    manager.dismissActivity()
                }
            }
        }
    }

    @ViewBuilder
    private var accessView: some View {
        let status = CalendarManager.shared.authorizationStatus
        NookWidgetEmptyState(
            systemImage: "clock.badge",
            title: status == .notDetermined ? String(localized: "See what's next") : String(localized: "No access to Calendar"),
            message: status == .notDetermined ? String(localized: "Your next events appear here.") : nil,
            actionTitle: status == .notDetermined ? String(localized: "Allow Access") : String(localized: "Open System Settings"),
            action: {
                Task { @MainActor in
                    if status == .notDetermined {
                        await CalendarManager.shared.requestFullAccess()
                        NextUpManager.shared.refresh()
                    } else {
                        await CalendarManager.shared.requestAccessFromUser()
                    }
                }
            }
        )
    }
}

/// One event: colour dot + title, countdown · time range, location, Join.
struct NextUpRowView: View {
    var item: NextUpItem
    var now: Date
    var isFirst: Bool

    private var startsSoon: Bool {
        !item.isAllDay && !item.isInProgress(at: now) && item.start.timeIntervalSince(now) <= 5 * 60
    }

    private var countdownStyle: AnyShapeStyle {
        if item.isInProgress(at: now) && !item.isAllDay { return AnyShapeStyle(Color.green) }
        if startsSoon { return AnyShapeStyle(Color.orange) }
        return AnyShapeStyle(.secondary)
    }

    /// The location unless it is only the meeting URL.
    private var shownLocation: String? {
        guard let location = item.location else { return nil }
        if location.lowercased().hasPrefix("http") || location.lowercased().hasPrefix("zoommtg:") { return nil }
        return location
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 7, height: 7)
                    Text(verbatim: item.title)
                        .font(isFirst ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // countdown (+ location on the compact rows)
                HStack(spacing: 0) {
                    Text(verbatim: NextUpFormat.countdown(for: item, now: now))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(countdownStyle)
                        .contentTransition(.numericText())
                        .layoutPriority(1)
                    if !isFirst, let location = shownLocation {
                        Text(verbatim: " · " + location)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .truncationMode(.tail)
                    }
                }
                .lineLimit(1)
                // first row: time range · location
                if isFirst {
                    Text(verbatim: [NextUpFormat.timeRange(for: item), shownLocation].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let meeting = item.meeting {
                Button { meeting.open() } label: {
                    Label("Join", systemImage: meeting.service == .facetime ? "video.fill" : "video")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .controlSize(.small)
                .nookButtonStyle(prominent: isFirst && (startsSoon || item.isInProgress(at: now)))
                .help(Text("Join \(meeting.service.displayName)"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isFirst ? 7 : 5)
        .nookCard(cornerRadius: NookWidgetMetrics.rowCornerRadius, highlighted: isFirst)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Closed-notch live activity

/// One side of the `.nextUp` live activity: leading = calendar symbol in the calendar's colour,
/// trailing = minutes until the start ("5 min", then "Now").
struct NextUpLiveActivityView: View {
    var side: LiveActivityView.ActivitySide

    var body: some View {
        let item = NextUpManager.shared.activityItem
        let color = item?.color ?? .orange
        switch side {
        case .leading:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .help(item?.title ?? "")
        case .trailing:
            if let item {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    Text(verbatim: NextUpFormat.compact(until: item.start, now: context.date))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                        .fixedSize()
                }
                .help(item.title)
                .accessibilityLabel(Text(verbatim: item.title))
            }
        }
    }
}

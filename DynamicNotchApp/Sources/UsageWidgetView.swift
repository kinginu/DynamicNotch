// Usage widget (2026-10-20), a Screen Time-like summary of the self-collected statistics
// (UsageTracker): today's total, the last 7 days as bars, today's pickups (unlocks) and the top 5
// apps with icons and bars relative to the most used one. 5 grid cells (250 pt). Apple-style per
// Support/NookWidgetChrome.swift. When recording is off the widget offers to turn it on in
// Settings (it never starts recording by itself).
import SwiftUI
import AppKit

struct UsageWidgetView: View {
    @State private var tracker = UsageTracker.shared
    @StoredSetting(.usageWidgetSettings) private var settings
    /// DEBUG previews: a fixed summary (and recording state) instead of the tracker's.
    var previewSummary: UsageSummary? = nil
    var previewEnabled: Bool? = nil

    private var enabled: Bool { previewEnabled ?? settings.trackingEnabled }

    var body: some View {
        Group {
            if enabled {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    // `revision` makes the view re-read after every save / setting change
                    let _ = tracker.revision
                    UsageSummaryView(summary: previewSummary ?? tracker.summary(at: context.date))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    UsageWidgetHeader(pickups: nil)
                    NookWidgetAccessState(
                        systemImage: "hourglass",
                        title: Text("Usage recording is off"),
                        actionTitle: "Turn On…",
                        prominent: true,
                        action: { NookSettingsNavigation.showWidgetSettings(.usage) }
                    )
                    NookWidgetFootnote(text: String(localized: "See which apps you use, recorded on this Mac only."),
                                       lineLimit: 2)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .nookWidgetFrame()
    }
}

struct UsageWidgetHeader: View {
    var pickups: Int?

    var body: some View {
        NookWidgetHeader("Usage", systemImage: "hourglass") {
            if let pickups {
                Text(pickups == 1 ? String(localized: "1 pickup") : String(format: String(localized: "%lld pickups"), pickups))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(String(localized: "Times this Mac was unlocked today"))
            }
        }
    }
}

struct UsageSummaryView: View {
    let summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            UsageWidgetHeader(pickups: summary.pickupsToday)
            HStack(alignment: .bottom, spacing: NookWidgetMetrics.spacing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: UsageFormatting.duration(summary.todayTotal))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                UsageWeekBars(week: summary.week, today: summary.today)
                    .frame(width: 126, height: 40)
            }
            if summary.topApps.isEmpty {
                NookWidgetPlaceholder(systemImage: "hourglass", title: Text("No app use recorded yet today."))
            } else {
                VStack(spacing: 3) {
                    let top = summary.topApps.first?.seconds ?? 1
                    ForEach(summary.topApps) { app in
                        UsageAppRow(app: app, fraction: top > 0 ? app.seconds / top : 0)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

/// The last 7 days, oldest first; today in the accent colour.
struct UsageWeekBars: View {
    let week: [(day: UsageDay, seconds: TimeInterval)]
    let today: UsageDay

    var body: some View {
        let peak = max(week.map(\.seconds).max() ?? 0, 1)
        let calendar = Calendar.current
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, entry in
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let h = entry.seconds > 0 ? max(geo.size.height * entry.seconds / peak, 2) : 1
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(entry.day == today ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                                .frame(height: h)
                        }
                    }
                    Text(verbatim: Self.letter(entry.day, calendar: calendar))
                        .font(.system(size: 9, weight: entry.day == today ? .semibold : .regular))
                        .foregroundStyle(entry.day == today ? .secondary : .tertiary)
                        .frame(height: 10)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: Self.weekday(entry.day, calendar: calendar)))
                .accessibilityValue(Text(verbatim: UsageFormatting.duration(entry.seconds)))
            }
        }
    }

    static func letter(_ day: UsageDay, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: day.start(in: calendar))
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    static func weekday(_ day: UsageDay, calendar: Calendar) -> String {
        let weekday = calendar.component(.weekday, from: day.start(in: calendar))
        let symbols = calendar.standaloneWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : day.key
    }
}

struct UsageAppRow: View {
    let app: UsageAppTotal
    /// Share of the most used app (0…1).
    let fraction: Double

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon = UsageAppIcons.icon(for: app.appID) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: app.appName.isEmpty ? app.appID : app.appName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(verbatim: UsageFormatting.duration(app.seconds))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(Color.accentColor.opacity(0.85))
                            .frame(width: max(geo.size.width * min(max(fraction, 0), 1), 3))
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: app.appName))
        .accessibilityValue(Text(verbatim: UsageFormatting.duration(app.seconds)))
    }
}

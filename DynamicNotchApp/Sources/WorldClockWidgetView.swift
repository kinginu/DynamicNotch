// World Clock widget (2026-10-20): a row of city tiles like the macOS World Clock widget.
// Each tile: short label (TOK), large time (12/24 h per settings / locale), the day and the hour
// difference from this Mac ("Yesterday" / "−16h"), light while it is daytime there and dark at
// night, optionally an analog mini-dial. Updates on every minute boundary (every second when
// seconds are shown). Width: WorldClockWidgetLayout (one tile per clock).
import SwiftUI
import AppKit

struct WorldClockWidgetView: View {
    @StoredSetting(.worldClocksWidgetSettings) private var settings
    /// DEBUG previews: a fixed time and/or settings instead of now / the stored ones.
    var previewDate: Date? = nil
    var previewSettings: WorldClockWidgetSettings? = nil

    var body: some View {
        let s = previewSettings ?? settings
        Group {
            if s.clocks.isEmpty {
                NookWidgetEmptyState(
                    systemImage: "globe",
                    title: String(localized: "No clocks"),
                    actionTitle: String(localized: "Add Clocks…"),
                    action: { NookSettingsNavigation.showWidgetSettings(.worldClocks) }
                )
            } else if let previewDate {
                tiles(s, at: previewDate)
            } else {
                TimelineView(WorldClockSchedule(everySecond: s.showSeconds)) { context in
                    tiles(s, at: context.date)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nookWidgetGalleryHook()
        #if DEBUG
        .onAppear { DebugHooks.installWorldClockHook() }
        #endif
    }

    private func tiles(_ s: WorldClockWidgetSettings, at date: Date) -> some View {
        HStack(spacing: WorldClockWidgetLayout.tileSpacing) {
            ForEach(s.clocks) { clock in
                WorldClockTile(clock: clock, date: date, settings: s)
                    .frame(width: WorldClockWidgetLayout.tileWidth(showSeconds: s.showSeconds))
            }
        }
        .nookWidgetFrame(alignment: .leading)
        .contextMenu {
            Button("World Clock Settings…") { NookSettingsNavigation.showWidgetSettings(.worldClocks) }
        }
    }
}

/// Minute (or second) boundaries.
struct WorldClockSchedule: TimelineSchedule {
    var everySecond: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let step: TimeInterval = everySecond ? 1 : 60
        // whole seconds since 2001-01-01 00:00 UTC: minute boundaries line up with every time
        // zone's minutes (all offsets are whole minutes)
        var next = (startDate.timeIntervalSinceReferenceDate / step).rounded(.down) * step
        return AnyIterator {
            defer { next += step }
            return Date(timeIntervalSinceReferenceDate: next)
        }
    }
}

// MARK: - Time maths

enum WorldClockMath {
    /// Seconds the clock's zone is ahead of this Mac's zone at `date` (negative = behind).
    static func offset(of zone: TimeZone, at date: Date, local: TimeZone = .current) -> Int {
        zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
    }

    /// −1 / 0 / +1: the calendar day at `date` in `zone` relative to this Mac's day.
    static func dayDifference(of zone: TimeZone, at date: Date, local: TimeZone = .current) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let there = cal.dateComponents([.year, .month, .day], from: date)
        cal.timeZone = local
        let here = cal.dateComponents([.year, .month, .day], from: date)
        let utc = Calendar(identifier: .gregorian)
        guard let a = utc.date(from: there), let b = utc.date(from: here) else { return 0 }
        return utc.dateComponents([.day], from: b, to: a).day ?? 0
    }

    /// "+9h", "−16h", "+5:30h", "0h".
    static func offsetText(_ seconds: Int) -> String {
        let sign = seconds > 0 ? "+" : (seconds < 0 ? "\u{2212}" : "")
        let minutes = abs(seconds) / 60
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(sign)\(h)h" : String(format: "%@%d:%02dh", sign, h, m)
    }

    static func dayText(_ difference: Int) -> String {
        switch difference {
        case ..<0: return String(localized: "Yesterday")
        case 1...: return String(localized: "Tomorrow")
        default: return String(localized: "Today")
        }
    }

    /// Hour (0–23), minute, second in `zone`.
    static func components(_ date: Date, in zone: TimeZone) -> (hour: Int, minute: Int, second: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Daytime there: 6:00–17:59.
    static func isDaytime(hour: Int) -> Bool { (6..<18).contains(hour) }

    /// The digits ("18:23", "6:23", "18:23:45") and the AM/PM symbol (nil in 24-hour mode).
    static func timeText(_ date: Date, in zone: TimeZone, twelveHour: Bool, seconds: Bool) -> (digits: String, period: String?) {
        let c = components(date, in: zone)
        var digits: String
        var period: String? = nil
        if twelveHour {
            let h = c.hour % 12 == 0 ? 12 : c.hour % 12
            digits = String(format: "%d:%02d", h, c.minute)
            let symbols = DateFormatter()
            symbols.locale = .autoupdatingCurrent
            period = c.hour < 12 ? symbols.amSymbol : symbols.pmSymbol
        } else {
            digits = String(format: "%02d:%02d", c.hour, c.minute)
        }
        if seconds { digits += String(format: ":%02d", c.second) }
        return (digits, period)
    }
}

// MARK: - Tile

struct WorldClockTile: View {
    let clock: WorldClock
    let date: Date
    let settings: WorldClockWidgetSettings

    var body: some View {
        let zone = clock.timeZone
        let parts = WorldClockMath.components(date, in: zone)
        let light = settings.tintByDaytime && WorldClockMath.isDaytime(hour: parts.hour)
        let ink: Color = light ? .black : .white
        let secondary: Color = ink.opacity(0.55)
        let offset = WorldClockMath.offset(of: zone, at: date)
        let dayDiff = WorldClockMath.dayDifference(of: zone, at: date)
        let time = WorldClockMath.timeText(date, in: zone, twelveHour: settings.usesTwelveHourClock,
                                           seconds: settings.showSeconds)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(verbatim: clock.shortLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if clock.isLocal {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(secondary)
                }
            }
            .foregroundStyle(ink)

            if settings.showAnalogDial {
                Spacer(minLength: 0)
                WorldClockDial(hour: parts.hour, minute: parts.minute, second: parts.second,
                               showSeconds: settings.showSeconds, ink: ink, light: light)
                    .frame(width: 58, height: 58)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: time.digits)
                    .font(.system(size: settings.showAnalogDial ? 22 : 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(ink)
                if let period = time.period {
                    Text(verbatim: period)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(secondary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: WorldClockMath.dayText(dayDiff))
                Text(verbatim: clock.isLocal ? String(localized: "This Mac") : WorldClockMath.offsetText(offset))
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NookWidgetMetrics.cornerRadius, style: .continuous)
                .fill(light ? Color(white: 0.93) : Color(white: 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NookWidgetMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(light ? 0 : 0.08), lineWidth: 1)
        )
        .help(Text(verbatim: "\(clock.displayName) — \(zone.localizedName(for: .generic, locale: .autoupdatingCurrent) ?? zone.identifier)"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(clock.displayName), \(time.digits)\(time.period.map { " " + $0 } ?? ""), \(WorldClockMath.dayText(dayDiff))\(clock.isLocal ? "" : ", " + WorldClockMath.offsetText(offset))"))
    }
}

// MARK: - Analog mini-dial

struct WorldClockDial: View {
    let hour: Int
    let minute: Int
    let second: Int
    let showSeconds: Bool
    let ink: Color
    let light: Bool

    var body: some View {
        Canvas { ctx, size in
            let d = min(size.width, size.height)
            let r = d / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let face = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: d, height: d))
            ctx.fill(face, with: .color(light ? .white : .black))
            ctx.stroke(face, with: .color(ink.opacity(0.15)), lineWidth: 0.75)

            // hour ticks
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi
                let major = i % 3 == 0
                let outer = r - 3, inner = r - (major ? 8 : 6)
                var p = Path()
                p.move(to: point(c, inner, a))
                p.addLine(to: point(c, outer, a))
                ctx.stroke(p, with: .color(ink.opacity(major ? 0.8 : 0.4)),
                           style: StrokeStyle(lineWidth: major ? 1.5 : 1, lineCap: .round))
            }

            let m = Double(minute) + Double(showSeconds ? second : 0) / 60
            let h = Double(hour % 12) + m / 60
            hand(ctx, c, length: r * 0.5, angle: h / 12 * 2 * .pi, width: 2.6, color: ink)
            hand(ctx, c, length: r * 0.78, angle: m / 60 * 2 * .pi, width: 1.8, color: ink)
            if showSeconds {
                hand(ctx, c, length: r * 0.84, angle: Double(second) / 60 * 2 * .pi, width: 0.9, color: .orange)
            }
            let dot = Path(ellipseIn: CGRect(x: c.x - 2.2, y: c.y - 2.2, width: 4.4, height: 4.4))
            ctx.fill(dot, with: .color(showSeconds ? .orange : ink))
        }
        .accessibilityHidden(true)
    }

    private func point(_ c: CGPoint, _ length: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: c.x + length * CGFloat(sin(angle)), y: c.y - length * CGFloat(cos(angle)))
    }

    private func hand(_ ctx: GraphicsContext, _ c: CGPoint, length: CGFloat, angle: Double, width: CGFloat, color: Color) {
        var p = Path()
        p.move(to: c)
        p.addLine(to: point(c, length, angle))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

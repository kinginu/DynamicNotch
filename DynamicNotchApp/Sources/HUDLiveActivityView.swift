// F5 (2026-10-20): one side of the `.hud` closed-notch live activity (HUDMonitor):
//   leading  = the kind's SF Symbol (speaker with variable waves / slash when muted, sun, keyboard
//              light), white like the other closed-notch activities;
//   trailing = a capsule fill bar (the level), dimmed while muted; when the level is unknown
//              (keyboard backlight without a readable level) the track shows the key's direction.
// The bar animates between readings, so key repeats read as one continuous HUD.
import SwiftUI

struct HUDLiveActivityView: View {
    var side: LiveActivityView.ActivitySide
    /// DEBUG previews: a fixed reading instead of HUDMonitor's.
    var preview: HUDMonitor.Reading? = nil

    private var reading: HUDMonitor.Reading? { preview ?? HUDMonitor.shared.reading }

    var body: some View {
        if let reading {
            switch side {
            case .leading: icon(reading)
            case .trailing: HUDLevelBar(reading: reading)
            }
        }
    }

    private func icon(_ r: HUDMonitor.Reading) -> some View {
        Image(systemName: Self.symbol(for: r), variableValue: r.kind == .volume && !r.muted ? r.level : nil)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.nonShockingWhite)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 22, alignment: .leading)
            .accessibilityLabel(Text(Self.accessibilityName(for: r.kind)))
    }

    static func symbol(for r: HUDMonitor.Reading) -> String {
        switch r.kind {
        case .volume:
            return (r.muted || r.level == 0) ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness:
            return (r.level ?? 1) < 0.25 ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBacklight:
            return (r.level ?? 1) < 0.25 ? "light.min" : "light.max"
        }
    }

    static func accessibilityName(for kind: HUDMonitor.Kind) -> String {
        switch kind {
        case .volume: return "Volume"
        case .brightness: return "Display brightness"
        case .keyboardBacklight: return "Keyboard backlight"
        }
    }

    /// Width of each side (both sides use the same width so the camera housing stays centred).
    static func sideWidth(notchHeight: CGFloat) -> CGFloat {
        max(notchHeight, 24) + 52
    }
}

/// The trailing fill bar.
struct HUDLevelBar: View {
    var reading: HUDMonitor.Reading

    static let height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                if let level = reading.level {
                    Capsule()
                        .fill(Color.nonShockingWhite.opacity(reading.muted ? 0.35 : 1))
                        .frame(width: max(level > 0 ? Self.height : 0, geo.size.width * level))
                }
            }
            .frame(height: Self.height)
            .frame(maxHeight: .infinity)
            .overlay {
                if reading.level == nil, let glyph = directionGlyph {
                    Image(systemName: glyph)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.nonShockingWhite)
                }
            }
        }
        .animation(.snappy(duration: 0.18), value: reading.level)
        .animation(.easeOut(duration: 0.15), value: reading.muted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(HUDLiveActivityView.accessibilityName(for: reading.kind)))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var directionGlyph: String? {
        switch reading.direction {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .toggle: return "power"
        case nil: return nil
        }
    }

    private var accessibilityValue: String {
        if reading.muted { return "Muted" }
        guard let level = reading.level else { return "Unknown" }
        return "\(Int((level * 100).rounded()))%"
    }
}

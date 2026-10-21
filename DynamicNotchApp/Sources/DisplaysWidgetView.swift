// Displays widget (2026-10-20), like Control Center ▸ Display with every connected display:
// one card per display (built-in first, in NSScreen order otherwise) with its name, the current
// input of external monitors (read-only chip), and sliders for brightness, plus contrast and
// volume for DDC/CI monitors when turned on in the settings and supported by the monitor.
// Apple-style per Support/NookWidgetChrome.swift and WidgetUI/; 5 grid cells (250 pt), more cards scroll
// vertically. Data and writes: DisplayControlService (rate-limited, docs/displays.md).
import SwiftUI
import AppKit

enum DisplaysWidgetLayout {
    static let cells: CGFloat = 5
    static let sliderRowHeight: CGFloat = 22
}

struct DisplaysWidgetView: View {
    @State private var service = DisplayControlService.shared
    @StoredSetting(.displaysWidgetSettings) private var settings
    /// DEBUG previews / tests: another service (e.g. one on a fake monitor).
    var previewService: DisplayControlService? = nil
    /// DEBUG previews: settings instead of the stored ones.
    var previewSettings: DisplaysWidgetSettings? = nil

    private var source: DisplayControlService { previewService ?? service }
    private var config: DisplaysWidgetSettings { previewSettings ?? settings }

    private var displays: [DisplayInfo] {
        let list = config.visible(source.displays)
        return list.filter(\.isBuiltIn) + list.filter { !$0.isBuiltIn }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            NookWidgetHeader("Displays", systemImage: "display")
            if displays.isEmpty {
                NookWidgetEmptyState(
                    systemImage: "display",
                    title: String(localized: "No displays"),
                    message: source.lastRefresh == nil ? nil
                        : String(localized: "Turn displays on in Settings ▸ Widgets ▸ Displays.")
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(displays) { d in
                            DisplayCard(display: d, state: source.state(d.id), settings: config) { control, value in
                                source.set(control, to: value, on: d.id)
                            }
                        }
                    }
                }
                .scrollDisabled(displays.count <= 2)
            }
        }
        .nookWidgetFrame()
        .onAppear { if previewService == nil { service.setVisible(true) } }
        .onDisappear { if previewService == nil { service.setVisible(false) } }
    }
}

/// One display: name (+ input chip) and its sliders.
struct DisplayCard: View {
    let display: DisplayInfo
    let state: DisplayControlState
    let settings: DisplaysWidgetSettings
    let set: (DisplayControl, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: display.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(display.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if settings.showInputSource, let input = state.inputSource {
                    Text(verbatim: DDCInputSource.name(UInt16(input)))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                        .help(String(localized: "Current input"))
                }
            }
            if state.isAvailable(.brightness) {
                DisplaySliderRow(control: .brightness, value: state.brightness ?? 0,
                                 enabled: state.isSettable(.brightness),
                                 approximate: state.brightnessApproximate) { set(.brightness, $0) }
            } else {
                NookWidgetFootnote(text: unavailableText, lineLimit: 2, minimumScaleFactor: 0.85)
                    .frame(minHeight: DisplaysWidgetLayout.sliderRowHeight, alignment: .leading)
            }
            if settings.showContrast, state.isAvailable(.contrast) {
                DisplaySliderRow(control: .contrast, value: state.contrast ?? 0,
                                 enabled: state.isSettable(.contrast)) { set(.contrast, $0) }
            }
            if settings.showVolume, state.isAvailable(.volume) {
                DisplaySliderRow(control: .volume, value: state.volume ?? 0,
                                 enabled: state.isSettable(.volume)) { set(.volume, $0) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .nookCard(cornerRadius: NookWidgetMetrics.rowCornerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(display.name))
    }

    private var unavailableText: String {
        if display.isBuiltIn { return String(localized: "Brightness unavailable") }
        switch state.ddc {
        case .disabled, .notApplicable: return String(localized: "DDC/CI is off")
        case .probing: return String(localized: "Checking DDC/CI…")
        case .available: return String(localized: "Brightness unavailable")
        case .unavailable: return String(localized: "This monitor does not answer DDC/CI")
        }
    }
}

struct DisplaySliderRow: View {
    let control: DisplayControl
    let value: Double
    var enabled: Bool = true
    var approximate: Bool = false
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: 0...1)
                .controlSize(.mini)
                .disabled(!enabled)
                .accessibilityLabel(Text(DisplaysWidgetSettingsView.controlName(control)))
            Text(verbatim: (approximate ? "≈" : "") + "\(Int((value * 100).rounded()))%")
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
                .lineLimit(1)
        }
        .frame(height: DisplaysWidgetLayout.sliderRowHeight)
        .help(approximate ? String(localized: "Approximate value (read from the I/O Registry)") : "")
    }

    private var symbol: String {
        switch control {
        case .brightness: return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .contrast:   return "circle.lefthalf.filled"
        case .volume:     return value <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .input:      return "rectangle.connected.to.line.below"
        }
    }
}

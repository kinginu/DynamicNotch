// Batteries widget (2026-10-20), like macOS Notification Center's Batteries widget: one row
// per device — device icon, name, percentage and a battery glyph (charging bolt, red when low).
// Apple-style per Support/NookWidgetChrome.swift. Up to `BatteriesWidgetLayout.rowsPerColumn` rows
// fit one column (4 grid cells, 200 pt); more devices use two columns (8 cells, 400 pt), beyond
// that the list scrolls. Data: BatteryDevicesManager.
import SwiftUI
import AppKit

enum BatteriesWidgetLayout {
    static let rowsPerColumn = 5
    static let rowHeight: CGFloat = 30
    static let oneColumnCells: CGFloat = 4
    static let twoColumnCells: CGFloat = 8

    /// Grid cells for the devices currently shown (NookWidgetLayout.cells(of: .batteries)).
    static func preferredCells() -> CGFloat {
        guard Thread.isMainThread else { return oneColumnCells }
        return MainActor.assumeIsolated {
            let count = SettingsStore[.batteriesWidgetSettings].visible(BatteryDevicesManager.shared.devices).count
            return count > rowsPerColumn ? twoColumnCells : oneColumnCells
        }
    }
}

struct BatteriesWidgetView: View {
    @State private var manager = BatteryDevicesManager.shared
    @StoredSetting(.batteriesWidgetSettings) private var settings
    /// DEBUG previews: fixed devices instead of the manager's.
    var previewDevices: [BatteryDevice]? = nil

    private var devices: [BatteryDevice] { settings.visible(previewDevices ?? manager.devices) }

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            NookWidgetHeader("Batteries", systemImage: "battery.100percent")
            if devices.isEmpty {
                NookWidgetEmptyState(
                    systemImage: "battery.0percent",
                    title: String(localized: "No batteries"),
                    message: manager.lastRefresh == nil && previewDevices == nil ? nil
                        : String(localized: "Connected devices with a battery appear here.")
                )
            } else {
                list
            }
        }
        .nookWidgetFrame()
        .onAppear { if previewDevices == nil { manager.setVisible(true) } }
        .onDisappear { if previewDevices == nil { manager.setVisible(false) } }
        .onChange(of: settings.refreshInterval) { _, _ in manager.reschedule() }
    }

    @ViewBuilder
    private var list: some View {
        let twoColumns = devices.count > BatteriesWidgetLayout.rowsPerColumn
        let columns = twoColumns
            ? [GridItem(.flexible(), spacing: NookWidgetMetrics.spacing), GridItem(.flexible(), spacing: NookWidgetMetrics.spacing)]
            : [GridItem(.flexible())]
        ScrollView(.vertical, showsIndicators: false) {
            // column-major order in two columns would need a fixed split; row-major keeps the
            // sorted order readable left to right like Notification Center's grid
            LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
                ForEach(devices) { device in
                    BatteryDeviceRow(device: device)
                }
            }
        }
        .scrollDisabled(devices.count <= BatteriesWidgetLayout.rowsPerColumn * (twoColumns ? 2 : 1))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct BatteryDeviceRow: View {
    let device: BatteryDevice

    var body: some View {
        HStack(spacing: 6) {
            NookIconBadge(systemImage: device.kind.systemImage, diameter: 24, symbolSize: 12)
            Text(device.name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(device.percent)%")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(device.isLowPower ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .fixedSize()
            if device.isThisMac { ChargeLimitBadge() }  // F1: "Limit charging to 80 %" (ChargeLimitViews.swift)
            BatteryGlyph(percent: device.percent, isCharging: device.isCharging,
                         isPluggedIn: device.isPluggedIn, isLow: device.isLowPower)
        }
        .frame(height: BatteriesWidgetLayout.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(device.name))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
        let level = String(format: String(localized: "%lld percent"), device.percent)
        if device.isCharging { return String(format: String(localized: "%@, charging"), level) }
        if device.isLowPower { return String(format: String(localized: "%@, low battery"), level) }
        return level
    }
}

/// Battery outline with a fill proportional to the level: green while charging (with a bolt), red
/// when low, else the primary colour. A plug when on external power but not charging (full / held).
struct BatteryGlyph: View {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool = false
    var isLow: Bool

    private let size = CGSize(width: 22, height: 11)

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.7), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill)
                    .frame(width: max((size.width - 4) * CGFloat(min(max(percent, 0), 100)) / 100, percent > 0 ? 2 : 0))
                    .padding(2)
            }
            .frame(width: size.width, height: size.height)
            .overlay {
                // the bolt / plug is cut out of the glyph, like the menu bar battery icon
                if isCharging || isPluggedIn {
                    Image(systemName: isCharging ? "bolt.fill" : "powerplug.portrait.fill")
                        .font(.system(size: 8.5, weight: .black))
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            RoundedRectangle(cornerRadius: 1)
                .fill(.secondary.opacity(0.7))
                .frame(width: 1.5, height: 4)
        }
        .accessibilityHidden(true)
    }

    private var fill: Color {
        if isCharging { return .green }
        if isLow { return .red }
        return .primary
    }
}

// Bluetooth widget (2026-10-20), like Control Center's Bluetooth module: the paired devices
// (icon by device class, name, Connected / Not Connected), click a device to connect or disconnect
// it (spinner while in progress, a short error toast on failure), right-click to add it to the
// favourites. The header shows whether Bluetooth is on (read only). 4 grid cells (200 pt).
// Apple-style per Support/NookWidgetChrome.swift. Data: BluetoothWidgetModel.
import SwiftUI
import AppKit
import CoreBluetooth

/// Grid width of the Bluetooth widget (NookWidgetLayout.cells(of: .bluetooth)).
enum BluetoothWidgetLayout {
    static var cells: CGFloat {
        #if DEBUG   // DN_BT_PREVIEW_DIR launch hook (BluetoothWidgetDebug.swift)
        BluetoothWidgetDebug.autoRunIfRequested()
        #endif
        return 4   // 200 pt
    }
}

/// What the widget shows (the live model, or fixed DEBUG preview data).
struct BluetoothWidgetDisplayState {
    var authorization: CBManagerAuthorization
    var power: BluetoothWidgetModel.PowerState
    var devices: [BluetoothWidgetDevice]
    var inFlight: [String: BluetoothWidgetModel.Operation] = [:]
    var toast: String? = nil
    var batteries: [String: Int] = [:]
}

struct BluetoothWidgetView: View {
    @State private var model = BluetoothWidgetModel.shared
    @StoredSetting(.bluetoothWidgetSettings) private var settings
    /// DEBUG previews: fixed state instead of the model's.
    var preview: BluetoothWidgetDisplayState? = nil

    private var state: BluetoothWidgetDisplayState {
        if let preview { return preview }
        var s = BluetoothWidgetDisplayState(authorization: model.authorization, power: model.power,
                                            devices: model.devices, inFlight: model.inFlight,
                                            toast: model.toast?.message)
        for d in model.devices where d.isConnected {
            if let p = model.batteryPercent(for: d) { s.batteries[d.id] = p }
        }
        return s
    }

    var body: some View {
        let state = self.state
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            header(state)
            content(state)
        }
        .nookWidgetFrame()
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                BluetoothToastView(message: toast)
                    .padding(.horizontal, NookWidgetMetrics.padding)
                    .padding(.bottom, NookWidgetMetrics.padding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: state.toast)
        .onAppear {
            guard preview == nil else { return }
            model.start()
            #if DEBUG
            BluetoothWidgetDebug.install()
            #endif
        }
        .onDisappear { if preview == nil { model.stop() } }
    }

    private func header(_ state: BluetoothWidgetDisplayState) -> some View {
        NookWidgetHeader("Bluetooth", systemImage: "dot.radiowaves.left.and.right", spacing: 6) {
            if state.power == .on || state.power == .off {
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.power == .on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                    Text(state.power == .on ? "On" : "Off")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(state.power == .on ? "Bluetooth is on" : "Bluetooth is off"))
            }
        }
    }

    @ViewBuilder
    private func content(_ state: BluetoothWidgetDisplayState) -> some View {
        switch state.authorization {
        case .notDetermined:
            NookWidgetEmptyState(
                systemImage: "dot.radiowaves.left.and.right",
                title: String(localized: "Bluetooth Access"),
                message: String(localized: "Allow access to show your paired devices."),
                actionTitle: String(localized: "Allow"),
                action: preview == nil ? { model.requestAccess() } : {}
            )
        case .denied, .restricted:
            NookWidgetEmptyState(
                systemImage: "exclamationmark.triangle",
                title: String(localized: "Bluetooth access is off"),
                message: String(localized: "Turn on DynamicNotch in Privacy & Security ▸ Bluetooth."),
                actionTitle: String(localized: "Open System Settings"),
                action: preview == nil ? { model.openPrivacySettings() } : {}
            )
        default:
            switch state.power {
            case .off:
                NookWidgetEmptyState(
                    systemImage: "dot.radiowaves.left.and.right",
                    title: String(localized: "Bluetooth is off"),
                    message: String(localized: "Turn it on in Control Center."),
                    actionTitle: String(localized: "Bluetooth Settings"),
                    action: preview == nil ? { model.openBluetoothSettings() } : {}
                )
            case .unavailable:
                NookWidgetEmptyState(systemImage: "dot.radiowaves.left.and.right",
                                     title: String(localized: "Bluetooth is unavailable"))
            case .on, .unknown:
                let devices = settings.visible(state.devices)
                if devices.isEmpty {
                    NookWidgetEmptyState(
                        systemImage: settings.showOnlyFavourites ? "star" : "dot.radiowaves.left.and.right",
                        title: settings.showOnlyFavourites ? String(localized: "No favourite devices") : String(localized: "No devices"),
                        message: settings.showOnlyFavourites
                            ? String(localized: "Right-click a device to add it to the favourites, or turn off Show only favourites.")
                            : String(localized: "Paired devices appear here.")
                    )
                } else {
                    list(devices, state: state)
                }
            }
        }
    }

    private func list(_ devices: [BluetoothWidgetDevice], state: BluetoothWidgetDisplayState) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(devices) { device in
                    BluetoothDeviceRow(
                        device: device,
                        operation: state.inFlight[device.id],
                        battery: state.batteries[device.id],
                        isFavourite: settings.isFavourite(device.id),
                        toggle: { if preview == nil { model.toggle(device) } },
                        toggleFavourite: { settings.toggleFavourite(device.id) }
                    )
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct BluetoothDeviceRow: View {
    let device: BluetoothWidgetDevice
    var operation: BluetoothWidgetModel.Operation?
    var battery: Int?
    var isFavourite: Bool
    var toggle: () -> Void
    var toggleFavourite: () -> Void

    @State private var hovering = false

    private var statusText: LocalizedStringKey {
        switch operation {
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case nil: return device.isConnected ? "Connected" : "Not Connected"
        }
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                NookIconBadge(systemImage: device.kind.systemImage, diameter: 26, symbolSize: 13,
                              isActive: device.isConnected)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
                        Text(verbatim: device.displayName)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if isFavourite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if operation != nil {
                    ProgressView().controlSize(.mini)
                } else if let battery, device.isConnected {
                    Text(verbatim: "\(battery)%")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(battery <= 20 ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous)
                    .fill(.primary.opacity(hovering ? 0.08 : 0))
            )
        }
        .buttonStyle(.plain)
        .disabled(operation != nil)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(device.isConnected ? "Disconnect" : "Connect", action: toggle)
                .disabled(operation != nil)
            Button(isFavourite ? "Remove from Favourites" : "Add to Favourites", action: toggleFavourite)
        }
        .help(Text(device.isConnected ? "Click to disconnect" : "Click to connect"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: device.displayName))
        .accessibilityValue(Text(statusText))
        .accessibilityAddTraits(.isButton)
    }
}

struct BluetoothToastView: View {
    var message: String

    var body: some View {
        Label {
            Text(verbatim: message)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        // opaque (not glass): it sits on top of the device list and must stay readable
        .background(
            RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

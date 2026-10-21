// Storage widget (2026-10-20): one ring per mounted volume (used fraction; orange from 85 %,
// red from 95 %) with the volume's SF Symbol inside, its name, and free space in GB or the
// percentage used (Settings ▸ Widgets ▸ Storage). A single volume gets a large ring with details.
// Removable / external / disk-image / network volumes have an eject button. Apple-style per
// Support/NookWidgetChrome.swift; 4 grid cells (200 pt), more than 4 volumes scroll vertically.
// Data: StorageVolumesManager (60 s + NSWorkspace mount notifications).
import SwiftUI
import AppKit

enum StorageWidgetLayout {
    static let cells: CGFloat = 4
    static let ringDiameter: CGFloat = 50
    static let largeRingDiameter: CGFloat = 92
}

enum StorageFormat {
    /// Finder-style decimal sizes ("123.4 GB").
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func detail(_ v: StorageVolume, mode: StorageDisplayMode) -> String {
        switch mode {
        case .gigabytes: return String(format: String(localized: "%@ free"), bytes(v.availableBytes))
        case .percent:   return String(format: String(localized: "%lld%% used"), v.usedPercent)
        }
    }

    static func ringColor(_ fraction: Double) -> Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.85 { return .orange }
        return .accentColor
    }
}

struct StorageWidgetView: View {
    @State private var manager = StorageVolumesManager.shared
    @StoredSetting(.storageWidgetSettings) private var settings
    /// DEBUG previews: fixed volumes instead of the manager's.
    var previewVolumes: [StorageVolume]? = nil
    /// DEBUG previews: display mode instead of the stored one.
    var previewMode: StorageDisplayMode? = nil

    private var mode: StorageDisplayMode { previewMode ?? settings.displayMode }

    private var volumes: [StorageVolume] { settings.visible(previewVolumes ?? manager.volumes) }

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            NookWidgetHeader("Storage", systemImage: "internaldrive")
            if volumes.isEmpty {
                NookWidgetEmptyState(
                    systemImage: "internaldrive",
                    title: String(localized: "No volumes"),
                    message: manager.lastRefresh == nil && previewVolumes == nil ? nil
                        : String(localized: "Mounted disks appear here.")
                )
            } else if volumes.count == 1, let v = volumes.first {
                StorageLargeVolumeView(volume: v, mode: mode,
                                       isEjecting: manager.ejecting.contains(v.id),
                                       eject: { manager.eject(v) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid
            }
            if let error = manager.ejectError, previewVolumes == nil {
                NookWidgetFootnote(text: error, tone: .error, lineLimit: 2, minimumScaleFactor: 0.8)
                    .onTapGesture { manager.dismissEjectError() }
            }
        }
        .nookWidgetFrame()
        .onAppear {
            if previewVolumes == nil { manager.setVisible(true) }
            #if DEBUG
            StorageWidgetDebug.install()
            #endif
        }
        .onDisappear { if previewVolumes == nil { manager.setVisible(false) } }
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)],
                      alignment: .center, spacing: 6) {
                ForEach(volumes) { v in
                    StorageRingCell(volume: v, mode: mode,
                                    isEjecting: manager.ejecting.contains(v.id),
                                    eject: { manager.eject(v) })
                }
            }
        }
        .scrollDisabled(volumes.count <= 4)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Usage ring: track + used arc, the volume symbol in the middle.
struct StorageRing<Center: View>: View {
    var fraction: Double
    var diameter: CGFloat
    var lineWidth: CGFloat
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(fraction, 0.005))
                .stroke(StorageFormat.ringColor(fraction), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .padding(lineWidth / 2)
        .frame(width: diameter, height: diameter)
    }
}

/// Small eject button (glass / material circle).
struct StorageEjectButton: View {
    var name: String
    var isEjecting: Bool
    var diameter: CGFloat = 20
    var action: () -> Void

    var body: some View {
        if isEjecting {
            ProgressView()
                .controlSize(.mini)
                .frame(width: diameter, height: diameter)
        } else {
            NookRoundIconButton(systemImage: "eject.fill",
                                label: Text(String(format: String(localized: "Eject “%@”"), name)),
                                diameter: diameter, action: action)
        }
    }
}

struct StorageRingCell: View {
    let volume: StorageVolume
    let mode: StorageDisplayMode
    var isEjecting = false
    var eject: () -> Void = {}

    var body: some View {
        VStack(spacing: 3) {
            StorageRing(fraction: volume.usedFraction, diameter: StorageWidgetLayout.ringDiameter, lineWidth: 5) {
                Image(systemName: volume.kind.systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }
            .overlay(alignment: .topTrailing) {
                if volume.isEjectable {
                    StorageEjectButton(name: volume.name, isEjecting: isEjecting, diameter: 18, action: eject)
                        .offset(x: 8, y: -4)
                }
            }
            Text(volume.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.8)
            Text(StorageFormat.detail(volume, mode: mode))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .help(StorageAccessibility.summary(volume))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(volume.name))
        .accessibilityValue(Text(StorageAccessibility.summary(volume)))
    }
}

struct StorageLargeVolumeView: View {
    let volume: StorageVolume
    let mode: StorageDisplayMode
    var isEjecting = false
    var eject: () -> Void = {}

    var body: some View {
        VStack(spacing: 6) {
            StorageRing(fraction: volume.usedFraction, diameter: StorageWidgetLayout.largeRingDiameter, lineWidth: 8) {
                VStack(spacing: 1) {
                    Image(systemName: volume.kind.systemImage)
                        .font(.system(size: 18, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(volume.usedPercent)%")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
            HStack(spacing: 4) {
                Text(volume.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if volume.isEjectable {
                    StorageEjectButton(name: volume.name, isEjecting: isEjecting, action: eject)
                }
            }
            Text(mode == .gigabytes
                 ? String(format: String(localized: "%1$@ free of %2$@"),
                          StorageFormat.bytes(volume.availableBytes), StorageFormat.bytes(volume.totalBytes))
                 : StorageFormat.detail(volume, mode: mode))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(volume.name))
        .accessibilityValue(Text(StorageAccessibility.summary(volume)))
    }
}

enum StorageAccessibility {
    static func summary(_ v: StorageVolume) -> String {
        String(format: String(localized: "%1$@ used of %2$@, %3$@ free"),
               StorageFormat.bytes(v.usedBytes), StorageFormat.bytes(v.totalBytes), StorageFormat.bytes(v.availableBytes))
    }
}

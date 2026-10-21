import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Content of the open notch in modes .tray and .dragging (NotchView gives it a
//   fixed openWidth × (250 − notch height) frame). Layout (user decision 2026-10-20, ideal demo): one row —
//   - left (flexible): .tray → TrayFilesScrollView (or TrayEmptyView when empty);
//                      .dragging → the Tray drop target (DropAreaTrayTargetView);
//   - right (TrayLayout.airDropZoneWidth): the AirDrop zone (TrayAirDropZone), in both modes at
//     the same place and size, shown when Settings ▸ Nook ▸ Drop Area ▸ AirDrop is on.
//   The drop targets' frames (DropAreaCoordPreferenceKey) go to NotchViewModel.targetsCoords.
//   Keyboard shortcuts (Tray.setupKeyDownMonitor) are active while this view is on screen.
struct TrayView: View {
    @Environment(\.tray) private var environmentTray
    @Environment(\.notchViewModel) private var environmentViewModel
    @Environment(\.dynamicNotchState) private var envNookState // per-screen state
    @StoredSetting(.dropAreaSettings) private var dropSettings

    private var tray: Tray { environmentTray ?? Tray.shared }
    private var viewModel: NotchViewModel { environmentViewModel ?? .shared }

    var body: some View {
        let dragging = (envNookState ?? .shared).mode == .dragging
        HStack(spacing: TrayLayout.spacing) {
            Group {
                if dragging {
                    DropAreaTrayTargetView(viewModel: viewModel)
                        .transition(.opacity)
                } else if tray.files.isEmpty {
                    TrayEmptyView()
                } else {
                    TrayFilesScrollView(tray: tray, showsAirDropButton: !dropSettings.showAirDropTarget)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if dropSettings.showAirDropTarget {
                TrayAirDropZone(tray: tray, viewModel: viewModel, routed: dragging)
                    .frame(width: TrayLayout.airDropZoneWidth)
            }
        }
        .padding(TrayLayout.insets)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.2), value: dragging)
        .onPreferenceChange(DropAreaCoordPreferenceKey.self) { frames in
            if viewModel.targetsCoords != frames { viewModel.targetsCoords = frames }
        }
        .onAppear { tray.startKeyboardMonitoring() }
        .onDisappear {
            if !viewModel.targetsCoords.isEmpty { viewModel.targetsCoords = [:] }
            tray.stopKeyboardMonitoring()
            if tray.editingFile != nil { tray.editingFile = nil }
        }
    }
}

/// Shared geometry of the tray and of the drop targets (2026-10-20), so the drop
/// layout (.dragging) lines up with the open tray (.tray).
enum TrayLayout {
    /// width of the AirDrop zone on the right
    static let airDropZoneWidth: CGFloat = 150
    /// gap between the left column and the AirDrop zone
    static let spacing: CGFloat = NookWidgetMetrics.spacing
    static let insets = EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12)
}

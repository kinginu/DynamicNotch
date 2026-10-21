import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// The Tray drop target shown in the open notch while files are dragged over it
//   (mode .dragging). It takes the place of the tray's file strip (left); the AirDrop zone
//   (TrayAirDropZone) stays on the right at the same size as in the open tray, so the drop layout
//   and the tray layout match (TrayView / TrayLayout, 2026-10-20). The drop itself is received by
//   the notch-wide AppKit destination (FileDropView / NotchDropController), which routes it to
//   NotchViewModel.hoveredDropTargetID; TrayView publishes the targets' frames into
//   NotchViewModel.targetsCoords.
struct DropAreaTrayTargetView: View {
    var viewModel: NotchViewModel

    private var hovered: String? { viewModel.hoveredDropTargetID }

    var body: some View {
        DropAreaTargetView(id: NotchDropTarget.tray.rawValue,
                           icon: .symbol("tray.and.arrow.down.fill"),
                           title: "Tray",
                           subtitle: "Drop files here",
                           // the tray is the default target when the pointer is between targets
                           isHovered: hovered == NotchDropTarget.tray.rawValue
                               || (hovered == nil && viewModel.droppingCoords != nil))
    }
}

/// The AirDrop zone on the right of the open tray (user decision 2026-10-20,
/// ideal demo: tray files on the left, AirDrop target on the right).
///   - `.tray`: dropping files on it — tray files dragged out of the strip, or a Finder drag
///     released directly on it — sends them via AirDrop (AirDropZoneDropView →
///     NotchDropTempFiles.airDrop(pasteboard:)); clicking it sends the selected tray files (all
///     files when nothing is selected).
///   - `.dragging` (`routed`): drawn only; NotchDropController routes the drop through
///     NotchViewModel.hoveredDropTargetID, as for the Tray card.
struct TrayAirDropZone: View {
    var tray: Tray
    var viewModel: NotchViewModel
    /// the notch is in .dragging (drop routed by NotchDropController)
    var routed: Bool

    @State private var directTargeted = false
    @State private var pointerHover = false

    private var isTargeted: Bool {
        routed ? viewModel.hoveredDropTargetID == NotchDropTarget.airDrop.rawValue : directTargeted
    }

    private var clickTargets: [TrayFile] { tray.selectedFiles.isEmpty ? tray.files : tray.selectedFiles }

    var body: some View {
        DropAreaTargetView(id: NotchDropTarget.airDrop.rawValue,
                           icon: .airDrop,
                           title: "AirDrop",
                           subtitle: "Drop to send",
                           isHovered: isTargeted,
                           isPointerHovered: !routed && pointerHover && !clickTargets.isEmpty)
            .overlay {
                if !routed {
                    AirDropZoneDropView(
                        toolTip: String(localized: "Click or drop files to send via AirDrop"),
                        onTargetedChange: { directTargeted = $0 },
                        onHoverChange: { pointerHover = $0 },
                        onClick: {
                            let urls = clickTargets.map(\.url)
                            if !urls.isEmpty { NotchDropTempFiles.airDrop(urls) }
                        })
                }
            }
            .onChange(of: routed) { _, _ in
                directTargeted = false
                pointerHover = false
            }
    }
}

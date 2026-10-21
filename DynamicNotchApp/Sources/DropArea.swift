import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Drop area placeholder. Used where a plain
//   "drop files here" area is wanted; the notch's drop handling lives in NotchDropController.
struct DropArea: View {
    var body: some View {
        TrayEmptyView()
            .frame(minWidth: 100, minHeight: 60)
    }
}

// MARK: - AirDrop zone destination (open tray)

/// AppKit drop destination in front of the open tray's AirDrop zone (TrayAirDropZone). The
/// notch-wide destination (FileDropView / NotchDropController) ignores drags that start inside the
/// app, so dragging tray files onto the zone needs its own destination; Finder drags released
/// directly on the zone while the tray is open land here too. The view also takes the zone's
/// clicks (send the selected / all tray files) and reports pointer hover, like the tray tiles'
/// CustomDraggableView in front of their SwiftUI content.
struct AirDropZoneDropView: NSViewRepresentable {
    /// tooltip (SwiftUI's .help does not reach through the AppKit view in front)
    var toolTip: String
    /// a drag is over the zone
    var onTargetedChange: (Bool) -> Void
    /// the pointer (no drag) is over the zone
    var onHoverChange: (Bool) -> Void
    var onClick: () -> Void

    func makeNSView(context: Context) -> ZoneView {
        let view = ZoneView(frame: .zero)
        update(view)
        return view
    }

    func updateNSView(_ nsView: ZoneView, context: Context) {
        update(nsView)
    }

    private func update(_ view: ZoneView) {
        if view.toolTip != toolTip { view.toolTip = toolTip }
        view.onTargetedChange = onTargetedChange
        view.onHoverChange = onHoverChange
        view.onClick = onClick
    }

    static func dismantleNSView(_ nsView: ZoneView, coordinator: ()) {
        nsView.setTargeted(false)
        nsView.setHovering(false)
    }

    final class ZoneView: NSView {
        var onTargetedChange: (Bool) -> Void = { _ in }
        var onHoverChange: (Bool) -> Void = { _ in }
        var onClick: () -> Void = {}
        private var targeted = false
        private var hovering = false
        private var pressed = false
        private var trackingArea: NSTrackingArea?

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes(NotchDropController.registeredTypes)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            registerForDraggedTypes(NotchDropController.registeredTypes)
        }

        func setTargeted(_ value: Bool) {
            guard targeted != value else { return }
            targeted = value
            onTargetedChange(value)
        }

        func setHovering(_ value: Bool) {
            guard hovering != value else { return }
            hovering = value
            onHoverChange(value)
        }

        // MARK: Pointer

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { setHovering(true) }
        override func mouseExited(with event: NSEvent) { setHovering(false) }

        override func mouseDown(with event: NSEvent) { pressed = true }

        override func mouseUp(with event: NSEvent) {
            defer { pressed = false }
            guard pressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            onClick()
        }

        // MARK: NSDraggingDestination

        private func accepts(_ info: NSDraggingInfo) -> Bool {
            info.draggingPasteboard.canReadObject(forClasses: NotchDropController.readableClasses, options: nil)
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard accepts(sender) else { return [] }
            setTargeted(true)
            return .copy
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard accepts(sender) else { return [] }
            setTargeted(true)
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) { setTargeted(false) }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            setTargeted(false)
            let pasteboard = sender.draggingPasteboard
            if sender.draggingSource != nil,
               let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                                 options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                // tray files: the tray must not delete them ("Remove files after dragging them
                // out") while AirDrop still reads them
                AirDropZoneDrops.record(urls)
            }
            return NotchDropTempFiles.airDrop(pasteboard: pasteboard)
        }

        override func draggingEnded(_ sender: NSDraggingInfo) { setTargeted(false) }
    }
}

/// URLs of tray files that the last in-app drag delivered to the AirDrop zone.
/// The tray tiles' drag sources check it in `onDropCompleted` (which runs right after the drop) so
/// "Remove files after dragging them out" does not delete files that are being sent.
@MainActor
enum AirDropZoneDrops {
    private static var recent: Set<URL> = []

    static func record(_ urls: [URL]) {
        recent = Set(urls.map(\.standardizedFileURL))
        // the drag source's end callback follows the drop immediately; never keep stale entries
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { recent.removeAll() }
    }

    /// True (and forgets them) when `urls` were just dropped on the AirDrop zone.
    static func consume(_ urls: [URL]) -> Bool {
        let set = Set(urls.map(\.standardizedFileURL))
        guard !set.isEmpty, set.isSubset(of: recent) else { return false }
        recent.subtract(set)
        return true
    }
}

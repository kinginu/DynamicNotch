import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// NSView that drags a set of file URLs (with an optional SwiftUI drag preview) and accepts
//   file-URL drops. NSDraggingSource is declared on the class: generic classes can't add @objc
//   conformances in extensions.
class CustomDraggableView<A: View>: NSView, NSDraggingSource {


    // SwiftUI view rendered into the drag image; nil drags the URL's own image.
    var dragPreview: (() -> A)?

    // returning false for a point makes the view transparent to clicks there
    var hitTestBlock: ((CGPoint) -> Bool)?

    // URLs dragged out of / dropped onto the view.
    var selectedURLs: [URL] = []

    // window-space location of the last mouse-down (nil when no press is in progress)
    var initialMouseDownLocation: CGPoint?

    // called after URLs were dropped onto the view
    var onSelect: () -> Void = {}

    // Closure called when a drag session ends.
    var onDropCompleted: (Bool) -> Void = { _ in }

    // Minimum pointer travel before initiating drag.
    var minimumDragDistance: CGFloat = 3.0

    // The view sits in front of the tray tile, so it also handles the tile's clicks
    //   (selection / double-click = open) and its context menu.
    var onClick: ((NSEvent) -> Void)?
    var menuProvider: (() -> NSMenu?)?
    private var dragStarted = false
    /// keeps the source alive while a session runs (the notch may close and remove the view)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?() ?? super.menu(for: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { initialMouseDownLocation = nil }
        if !dragStarted, initialMouseDownLocation != nil {
            onClick?(event)
        }
    }

    // MARK: - Initializers

    required init?(coder: NSCoder) {
        self.onSelect = {}
        self.onDropCompleted = { _ in }
        self.selectedURLs = []
        self.dragPreview = nil
        self.hitTestBlock = nil
        self.initialMouseDownLocation = nil
        self.minimumDragDistance = 3.0
        super.init(coder: coder)
    }

    override init(frame: NSRect) {
        self.onSelect = {}
        self.onDropCompleted = { _ in }
        self.selectedURLs = []
        self.dragPreview = nil
        self.hitTestBlock = nil
        self.initialMouseDownLocation = nil
        self.minimumDragDistance = 3.0
        super.init(frame: frame)
    }

    // MARK: - Drag Item Factory

    // One dragging item per URL: the rendered preview (centred on the view) when `dragPreview`
    //   is set, otherwise the URL itself.
    func getDraggingItem(for url: URL) -> NSDraggingItem {
        let nsurl = url as NSURL

        let item = NSDraggingItem(pasteboardWriter: nsurl)

        if let previewClosure = dragPreview {
            let previewView = previewClosure()

            // render the SwiftUI view into an NSImage through an NSHostingView
            let hostingView = NSHostingView(rootView: previewView)
            hostingView.frame.size = hostingView.fittingSize

            let bounds = hostingView.bounds
            guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
                // Fallback: render failed → use URL as drag image
                item.setDraggingFrame(self.bounds, contents: nsurl)
                return item
            }
            hostingView.cacheDisplay(in: bounds, to: bitmap)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(bitmap)

            // centre the image on the view (frame is in view coordinates)
            let frame = NSRect(x: self.bounds.midX - bounds.width / 2, y: self.bounds.midY - bounds.height / 2,
                               width: bounds.width, height: bounds.height)
            item.setDraggingFrame(frame, contents: image)
        } else {
            let bounds = self.bounds
            item.setDraggingFrame(bounds, contents: nsurl)
        }

        return item
    }

    // MARK: - Hit Testing Override

    // `hitTestBlock` returning false lets the click through to the views behind.
    override func hitTest(_ point: CGPoint) -> NSView? {
        if let block = hitTestBlock {
            if !block(point) {
                return nil
            }
        }
        return super.hitTest(point)
    }

    // MARK: - Mouse Event Handlers (Drag Initiation)

    // Records where the press started, for the distance threshold in mouseDragged.
    override func mouseDown(with event: NSEvent) {
        let location = event.locationInWindow
        self.initialMouseDownLocation = location
        self.dragStarted = false
    }

    // Once the pointer has moved `minimumDragDistance`, starts one dragging session with an item
    //   per selected URL.
    override func mouseDragged(with event: NSEvent) {
        guard let initialLocation = initialMouseDownLocation, !dragStarted, !selectedURLs.isEmpty else { return }

        let currentLocation = event.locationInWindow

        let deltaX = currentLocation.x - initialLocation.x
        let deltaY = currentLocation.y - initialLocation.y

        let distance = hypot(deltaX, deltaY)

        if distance < minimumDragDistance { return }

        var items: [NSDraggingItem] = []
        for url in selectedURLs {
            let dragItem = getDraggingItem(for: url)
            items.append(dragItem)
        }

        dragStarted = true
        DragSourceKeepAlive.views.append(self)
        let session = self.beginDraggingSession(with: items, event: event, source: self)

        // formation 1 = .none: the items keep their own frames
        session.draggingFormation = NSDraggingFormation(rawValue: 1) ?? .default
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: - Drag Destination (Drop Handling)

    // Accepts dropped file URLs: stores them in `selectedURLs` and calls `onSelect`.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        let readableClasses: [AnyClass] = [NSURL.self]

        guard let rawObjects = pasteboard.readObjects(forClasses: readableClasses, options: nil),
              !rawObjects.isEmpty else {
            return false
        }

        let newURLs: [URL] = rawObjects.compactMap { $0 as? URL }

        guard !newURLs.isEmpty else {
            return false
        }

        self.selectedURLs = newURLs

        self.onSelect()

        return true
    }

// MARK: - NSDraggingSource Conformance

    // file drags are copies
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    // Reports to `onDropCompleted` whether the drag ended in a drop (any operation but none /
    //   delete).
    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        let success = operation != .delete && operation != []
        DragSourceKeepAlive.views.removeAll { $0 === self }
        dragStarted = false
        initialMouseDownLocation = nil
        onDropCompleted(success)
    }

// MARK: - NSDraggingDestination Conformance

    // only file URLs are accepted
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        guard let types = pasteboard.types,
              types.contains(.fileURL) else {
            return []
        }
        return .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {}
}

/// keeps drag sources alive while their session runs (the notch may close and
/// remove the source view mid-drag).
enum DragSourceKeepAlive {
    static var views: [NSView] = []
}

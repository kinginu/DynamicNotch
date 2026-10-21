import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// MARK: - FileDropView

// NSViewRepresentable wrapping DropAreaView (custom NSView subclass)
// Bridges AppKit drag-and-drop to SwiftUI via Coordinator
// The coordinator owns a NotchDropController (Support/NotchDrop.swift),
//   which switches the notch into .dragging and routes the drop. An AppKit destination is used
//   instead of SwiftUI's onDrop because it sees drags over the whole footprint regardless of the
//   SwiftUI content in front of it, and it gets NSDraggingInfo (file promises, pasteboard).
struct FileDropView: NSViewRepresentable {
    typealias NSViewType = DropAreaView

    let viewModel: NotchViewModel

    func makeNSView(context: Context) -> DropAreaView {
        let view = DropAreaView(frame: .zero)
        view.dropDelegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DropAreaView, context: Context) {
        nsView.dropDelegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject {
        let controller: NotchDropController

        init(viewModel: NotchViewModel) {
            self.controller = NotchDropController(viewModel: viewModel)
            super.init()
        }
    }

    // MARK: - DropAreaView

    // NSView subclass implementing NSDraggingDestination protocol methods
    class DropAreaView: NSView {
        var exitTimer: Timer?

        var boundary: DropHoverBoundary = DropHoverBoundary()

        weak var dropDelegate: Coordinator?

        // MARK: - init(frame:)

        override init(frame: CGRect) {
            super.init(frame: frame)
            self.registerForDraggedTypes(NotchDropController.registeredTypes)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            self.registerForDraggedTypes(NotchDropController.registeredTypes)
        }

        // never take mouse clicks from the SwiftUI gesture layer in front; only
        //   answer hit tests while a drag from another app is in progress (drag-destination lookup).
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let controller = dropDelegate?.controller,
                  MainActor.assumeIsolated({ controller.externalDragActive }) else { return nil }
            return super.hitTest(point)
        }

        // MARK: - NSDraggingDestination

        // Logic:
        //   1. Invalidate exitTimer if set, then nil
        //   2. Get drag sequence number from sender
        //   3. Get window, convert bounds to screen coordinates
        //   4. Call boundary.enter(sequence: frame:)
        //   5. If drag source is same view (first-time drag), return .copy
        //   6. Otherwise delegate to dropDelegate?.draggingEntered(sender) ?? .copy
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            exitTimer?.invalidate()
            exitTimer = nil

            let sequence = sender.draggingSequenceNumber
            var screenBounds = bounds
            if let window = window {
                screenBounds = window.convertToScreen(convert(bounds, to: nil)) // window → screen
            }
            boundary.enter(sequence: sequence, frame: screenBounds)

            // self-drag check
            if sender.draggingSource as? NSView === self {
                return .copy
            }
            guard let controller = dropDelegate?.controller else { return [] }
            return MainActor.assumeIsolated { controller.draggingEntered(sender) }
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard let controller = dropDelegate?.controller else { return [] }
            return MainActor.assumeIsolated { controller.draggingUpdated(sender) }
        }

        // Logic:
        //   1. Invalidate exitTimer, set to nil
        //   2. Call boundary.end() — resets all boundary fields
        //   3. Delegate to dropDelegate?.performDragOperation(sender) ?? false
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            exitTimer?.invalidate()
            exitTimer = nil
            boundary.end()
            guard let controller = dropDelegate?.controller else { return false }
            return MainActor.assumeIsolated { controller.performDrop(sender) }
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

        // Sets exitTimer to schedule boundary.exit after a short delay
        // the controller debounces the close itself (re-entering cancels it)
        override func draggingExited(_ sender: NSDraggingInfo?) {
            exitTimer?.invalidate()
            exitTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.boundary.exit()
            }
            guard let controller = dropDelegate?.controller else { return }
            MainActor.assumeIsolated { controller.draggingExited() }
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            guard let controller = dropDelegate?.controller else { return }
            MainActor.assumeIsolated { controller.draggingEnded() }
        }
    }
}

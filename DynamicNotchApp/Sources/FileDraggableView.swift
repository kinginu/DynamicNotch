import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Call sites use FileDraggableView(urls:) { preview }.
//   Renders `content` and overlays a CustomDraggableView that starts an AppKit file drag of `urls`
//   with `content` as the drag image.
struct FileDraggableView<Content: View>: View {
    var urls: [URL] = []
    var onDropCompleted: (Bool) -> Void = { _ in }
    // clicks / context menu are handled by the AppKit view in front of `content`
    var onClick: ((NSEvent) -> Void)? = nil
    var menu: (() -> NSMenu?)? = nil
    /// drag image (defaults to `content`)
    var preview: (() -> AnyView)? = nil
    @ViewBuilder var content: () -> Content

    init(urls: [URL] = [], onDropCompleted: @escaping (Bool) -> Void = { _ in },
         onClick: ((NSEvent) -> Void)? = nil, menu: (() -> NSMenu?)? = nil,
         preview: (() -> AnyView)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.urls = urls
        self.onDropCompleted = onDropCompleted
        self.onClick = onClick
        self.menu = menu
        self.preview = preview
        self.content = content
    }

    var body: some View {
        content()
            .overlay {
                DragSource(urls: urls, onDropCompleted: onDropCompleted, onClick: onClick, menu: menu,
                           preview: preview ?? { AnyView(content()) })
            }
    }

    // NSViewRepresentable bridge to CustomDraggableView
    private struct DragSource: NSViewRepresentable {
        var urls: [URL]
        var onDropCompleted: (Bool) -> Void
        var onClick: ((NSEvent) -> Void)?
        var menu: (() -> NSMenu?)?
        var preview: () -> AnyView

        func makeNSView(context: Context) -> CustomDraggableView<AnyView> {
            CustomDraggableView<AnyView>(frame: .zero)
        }

        func updateNSView(_ nsView: CustomDraggableView<AnyView>, context: Context) {
            nsView.selectedURLs = urls
            nsView.dragPreview = preview
            nsView.onDropCompleted = onDropCompleted
            nsView.onClick = onClick
            nsView.menuProvider = menu
        }
    }
}

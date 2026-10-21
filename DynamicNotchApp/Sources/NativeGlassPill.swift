import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
//
// SwiftUI wrapper of NativeGlassPillView: passes the glass params, corner radius and the
//   radius / slab providers to the view and marks it for layout when they change.

import SwiftUI
import AppKit

#if false // [disabled] whole file: types do not match (canImport(DynamicNotch) is true inside the Xcode target)
//   The struct wraps NativeGlassPillView (NSView subclass) for SwiftUI
struct NativeGlassPill: NSViewRepresentable {
    // NSViewRepresentable NSViewType = NativeGlassPillView
    typealias NSViewType = NativeGlassPillView


    // Corner radius for the glass pill shape
    var cornerRadius: CGFloat = 0

    // Optional closure that provides radius for a given size
    var radiusProvider: ((CGSize) -> CGFloat)? = nil

    // Optional closure that provides slab array for a given size
    var slabsProvider: ((CGSize) -> [GlassSlab])? = nil

    func makeNSView(context: NSViewRepresentableContext<NativeGlassPill>) -> NativeGlassPillView {
        let view = NativeGlassPillView()

        view.params = NativeGlassParams(
            cornerRadius: cornerRadius,
            radiusProvider: radiusProvider,
            slabsProvider: slabsProvider
        )

        view.cornerRadius = cornerRadius

        view.radiusProvider = radiusProvider

        view.needsLayout = true

        view.slabsProvider = slabsProvider

        view.needsLayout = true

        view.translatesAutoresizingMaskIntoConstraints = true

        return view
    }

    func updateNSView(_ nsView: NativeGlassPillView, context: NSViewRepresentableContext<NativeGlassPill>) {
        nsView.params = NativeGlassParams(
            cornerRadius: cornerRadius,
            radiusProvider: radiusProvider,
            slabsProvider: slabsProvider
        )

        if nsView.cornerRadius != cornerRadius ||
           nsView.cornerRadius.isNaN ||
           cornerRadius.isNaN {
            nsView.cornerRadius = cornerRadius
            nsView.needsLayout = true
        }

        nsView.radiusProvider = radiusProvider
        nsView.needsLayout = true

        nsView.slabsProvider = slabsProvider
        nsView.needsLayout = true
    }
}
#endif

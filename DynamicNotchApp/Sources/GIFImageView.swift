import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AppKit
import SwiftUI

// NSViewRepresentable wrapper for displaying animated GIF images
//   via NSImageView. Reads MediaLiveActivitySettings from environment for
//   scaling quality. Applies CGAffineTransform scale on the backing layer.
struct GIFImageView: NSViewRepresentable {

    // MARK: - Properties

    let url: URL

    var animates: Bool = true

    // Environment value for scaling settings
    @Environment(\.mediaLiveActivitySettings) var mediaSettings

    // MARK: - NSViewRepresentable

    //   Allocs NSImageView, sets wantsLayer=true, animates, loads image from URL,
    //   configures interpolation/template, sets compression resistance,
    //   reads GIFScalingQuality from environment, applies CGAffineTransform scale on layer
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()

        imageView.wantsLayer = true

        imageView.animates = animates

        if let nsImage = NSImage(contentsOf: url) {
            configureImage(nsImage)
            imageView.image = nsImage
        }

        imageView.translatesAutoresizingMaskIntoConstraints = false

        imageView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250.0), for: .horizontal)
        imageView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250.0), for: .vertical)

        //   GIFScalingQuality.scalingMode: .scaleNone (0) or .scaleAxesIndependently (3)
        let scalingQuality = context.environment.mediaLiveActivitySettings.gifScalingQuality
        let scalingMode: NSImageScaling = (scalingQuality == .high) ? .scaleAxesIndependently : .scaleNone
        imageView.imageScaling = scalingMode

        //   Reads scale factor from environment and applies via layer.setAffineTransform
        if let layer = imageView.layer {
            let scaleFactor = context.environment.mediaLiveActivitySettings.gifScale  // field is gifScale
            let transform = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
            layer.setAffineTransform(transform)
        }

        return imageView
    }

    //   Same as makeNSView but dispatches image loading to main queue
    func updateNSView(_ nsView: NSImageView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let imageView = nsView else { return }

            if let nsImage = NSImage(contentsOf: url) {
                configureImage(nsImage)
                imageView.image = nsImage
            }

            let scalingQuality = context.environment.mediaLiveActivitySettings.gifScalingQuality
            let scalingMode: NSImageScaling = (scalingQuality == .high) ? .scaleAxesIndependently : .scaleNone
            imageView.imageScaling = scalingMode

            imageView.animates = animates
        }
    }

    // MARK: - Private Helpers

    //   Sets image template mode to false, configures NSGraphicsContext
    //   image interpolation based on GIFScalingQuality
    private func configureImage(_ image: NSImage) {
        image.isTemplate = false

        guard let context = NSGraphicsContext.current else { return }

        //   .high → NSImageInterpolation.high (3), else → .default (1)
        let quality = mediaSettings.gifScalingQuality
        let interpolation: NSImageInterpolation = (quality == .high) ? .high : .default
        context.imageInterpolation = interpolation
    }
}

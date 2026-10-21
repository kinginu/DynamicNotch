import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import SwiftUI

// Glass rendering aspect mode enumeration.
//   Contains a Simple struct that resolves to NativeGlassParams
//   for configuring glass blur/intensity/radius per display context.
enum GlassAspect {

    // Different glass rendering modes
    case fullBlur
    case subtleBlur
    case tinted(color: Color)
    case noBlur

    // MARK: - Simple (resolved glass params)

    // Resolves the current GlassAspect to concrete NativeGlassParams
    //   used by the rendering pipeline.
    struct Simple {

        // Blur radius
        var bluRadius: CGFloat = 12.0

        // Glass intensity
        var glassIntensity: CGFloat = 0.6

        // Tint color (if any)
        var tintColor: Color = .clear

        //   Builds the concrete params from the simple configuration
        var resolved: NativeGlassParams {
            NativeGlassParams(
                bluRadius: bluRadius,
                intensity: glassIntensity,
                tintColor: tintColor
            )
        }
    }
}

// NativeGlassParams is declared in NativeGlassParams.swift

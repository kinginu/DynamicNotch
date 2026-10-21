import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import SwiftUI
import AppKit
import CoreGraphics

struct NotchGesturer: View {
    @Environment(\.dynamicNotchState) private var envNookState

    @Environment(\.notchMode) private var nohNookMode

    @Environment(\.notchViewModel) private var envViewModel

    @Environment(\.gestureControlSettings) private var gesturControlSettings

    // the environment values are optional; fall back to the singletons
    private var nohNookState: DynamicNotchState { envNookState ?? .shared }
    private var viewModel: NotchViewModel { envViewModel ?? .shared }

    // Scrubbing needs: gestures allowed + open-state control enabled, and the notch is not locked or showing an indicator.
    var canScrub: Bool {
        guard gesturControlSettings.allowGestures, gesturControlSettings.controlOpenState else {
            return false
        }
        let nookState = nohNookState
        guard !nookState.locked, nookState.indicator == nil else {
            return false
        }
        return true
    }

    // 0 when nothing shows in the closed notch (no quick peeks, no live activities), else 0.15;
    //   0.225 while a pan is being cancelled.
    var restingScrubFloor: CGFloat {
        if viewModel.cancelPan { return 0.225 }
        let quickPeeks = nohNookState.quickPeeks
        if (quickPeeks == nil || quickPeeks!.isEmpty)
            && ActiveLiveActivitiesManager.shared.activeLiveActivities.isEmpty {
            return 0.0
        }
        return 0.15
    }

    // Haptic tick, then closes the notch with the liquidCloseFootprint animation and clears cancelPan.
    func commitScrubClose() {
        // Vibrate via helper
        vibrate()

        // Set NotchMode to close (false), withAnimation using liquidCloseFootprint
        // the environment's NotchMode is read-only; write DynamicNotchState.mode instead
        withAnimation(.liquidCloseFootprint) {
            nohNookState.mode = .closed
        }

        if viewModel.cancelPan {
            viewModel.cancelPan = false
        }
    }

    // Haptic tick, then opens the notch with the liquidOpenFootprint animation and clears cancelPan.
    func commitScrubOpen() {
        // Vibrate via helper
        vibrate()

        // Set NotchMode to open (true), withAnimation using liquidOpenFootprint
        // opens into the last-selected tab (nook or tray)
        withAnimation(.liquidOpenFootprint) {
            nohNookState.select(DynamicNotchState.preferredOpenMode == .tray ? .tray : .nook)
        }

        if viewModel.cancelPan {
            viewModel.cancelPan = false
        }
    }

    // Pan handlers driving NotchViewModel's scrub API
    //   (beginScrub / scrub(by:) / scrubWouldToggle / commitScrub / endScrub).
    private func onPan(_ size: CGSize, _ start: CGPoint, _ translation: CGSize) {
        guard canScrub else { return }
        let closing = nohNookState.mode != .closed
        if viewModel.scrubExpansion == nil {
            viewModel.beginScrub(floor: restingScrubFloor, closing: closing)
            viewModel.scrubExpansion = closing ? 1.0 : restingScrubFloor
        }
        // pulling down opens, pushing up closes; when closing, offset the delta so that
        // zero translation maps to a fully open (1.0) scrub position
        let floor = viewModel.scrubFloor
        let base: CGFloat = closing ? (1.25 - floor) * 300.0 / max(1.0 - floor, 0.01) : 0
        viewModel.scrub(by: base + translation.height)
        viewModel.scrubExpansion = viewModel.scrubRaw
    }

    private func onPanEnded(_ velocity: CGSize) {
        guard viewModel.scrubExpansion != nil else { return }
        let closing = viewModel.scrubClosing
        if viewModel.scrubWouldToggle(velocityY: velocity.height) {
            if closing {
                viewModel.commitScrub(to: restingScrubFloor)
                commitScrubClose()
            } else {
                viewModel.commitScrub(to: 1.0)
                commitScrubOpen()
            }
        }
        viewModel.endScrub()
    }

    // Gesture surface with changeTrack support, scrubbing floor, and commit open/close actions
    var body: some View {
        // Container view with GeometryReader providing size/point for gesturing
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            onPan(proxy.size, value.startLocation, value.translation)
                        }
                        .onEnded { value in
                            onPanEnded(value.velocity)
                        }
                )
        }
    }
}

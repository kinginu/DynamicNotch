import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import AVFoundation
import AppKit
import SwiftUI

// NSViewRepresentable wrapping a camera preview view.
//   Uses AVCaptureSession and AVCaptureVideoPreviewLayer for live camera feed.
struct CameraPreview: NSViewRepresentable {

    // Capture session reference
    var session: AVCaptureSession?

    func makeCoordinator() -> () {
        return ()
    }

    func makeNSView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        if let session = session {
            view.setupLayer(session: session)
        }
        return view
    }

    func updateNSView(_ nsView: VideoPreviewView, context: Context) {
        if let session = session {
            nsView.setupLayer(session: session)
        }
    }

    // MARK: - VideoPreviewView

    class VideoPreviewView: NSView {

        private var previewLayer: AVCaptureVideoPreviewLayer?

        override init(frame: NSRect) {
            super.init(frame: frame)
            self.wantsLayer = true
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            self.wantsLayer = true
        }

        //   Creates AVCaptureVideoPreviewLayer, sets session, adds as sublayer
        func setupLayer(session: AVCaptureSession) {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill

            self.layer?.addSublayer(layer)
            self.previewLayer = layer
        }

        override func layout() {
            super.layout()
            previewLayer?.frame = self.bounds
        }
    }
}

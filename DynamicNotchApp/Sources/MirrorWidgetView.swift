import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation
import SwiftUI
import AVFoundation
import CoreMedia

// MARK: - Layout (camera aspect ratio)

// 2026-10-20 (user decision): the mirror is no longer round and never crops the
//   camera. The video area is a rounded rectangle at the camera's native aspect ratio: its height is
//   the Nook row height (202 pt) minus the widget padding, and its width follows the aspect ratio
//   (16:9 → 331 × 186 pt, 4:3 → 248 × 186 pt). Before the real capture format is known the aspect
//   comes from the selected camera's active format, else 16:9 (Mac built-in cameras).
@Observable
final class MirrorWidgetLayout {
    static let shared = MirrorWidgetLayout()

    /// Height of a widget cell in the open Nook (same value as WidgetGalleryDebug.rowHeight).
    static let rowHeight: CGFloat = 202
    /// Aspect ratio used until a camera reports its format.
    static let fallbackAspect: CGFloat = 16.0 / 9.0

    /// Width / height of the camera image the widget shows.
    private(set) var aspect: CGFloat

    private init() {
        aspect = CameraManager.shared.selectedDevice.flatMap(Self.aspect(of:)) ?? Self.fallbackAspect
    }

    static func aspect(of device: AVCaptureDevice) -> CGFloat? {
        CameraManager.videoDimensions(of: device).map(aspect(of:))
    }

    static func aspect(of dims: CMVideoDimensions) -> CGFloat {
        CGFloat(dims.width) / CGFloat(dims.height)
    }

    /// Clamped to sane values (portrait 9:16 … ultra-wide 21:9) so a bogus format cannot blow up
    ///   the notch width.
    func update(_ newAspect: CGFloat?) {
        guard let newAspect, newAspect.isFinite else { return }
        let clamped = min(max(newAspect, 9.0 / 16.0), 21.0 / 9.0)
        if abs(clamped - aspect) > 0.001 { aspect = clamped }
    }

    /// Video area for a widget cell of `size`: the largest `aspect` rectangle inside the cell minus
    ///   the widget padding (aspect-fit; with a cell of `preferredCellWidth` it fills the height).
    func videoSize(in size: CGSize) -> CGSize {
        let maxW = max(size.width - 2 * NookWidgetMetrics.padding, 1)
        let maxH = max(size.height - 2 * NookWidgetMetrics.padding, 1)
        let width = min(maxW, maxH * aspect)
        return CGSize(width: width.rounded(.down), height: (width / aspect).rounded(.down))
    }

    /// Cell width at which the video fills the row height: row height minus padding, times the
    ///   aspect, plus padding (16:9 → 347 pt, 4:3 → 264 pt).
    func preferredCellWidth(rowHeight: CGFloat = MirrorWidgetLayout.rowHeight) -> CGFloat {
        ((rowHeight - 2 * NookWidgetMetrics.padding) * aspect + 2 * NookWidgetMetrics.padding).rounded(.up)
    }

    /// The same in 50 pt grid cells (NookWidgetLayout.cell), for `NookWidgetLayout.cells(of: .mirror)`
    ///   (16:9 → 6.94, 4:3 → 5.28). Reading it in a view body tracks `aspect`.
    func preferredCells(rowHeight: CGFloat = MirrorWidgetLayout.rowHeight) -> CGFloat {
        preferredCellWidth(rowHeight: rowHeight) / 50
    }
}

// MARK: - MirrorWidgetView

// Widget displaying a camera mirror
// inactive: placeholder fill (Color.selected / liquid glass), tap to start;
//   active: CameraPreview with a ProgressView while the session starts.
// setupCamera / stopCamera dispatch CameraManager calls on a .userInitiated queue
//   (CameraManager serializes them on its own session queue).
// the camera runs only while the widget is visible (stopped in onDisappear, i.e.
//   when the notch closes or the widget is removed); "Open camera automatically" starts it on
//   appear when access was already granted. Denied / no-camera states are shown in place.
// 2026-10-20 (user decision): no circle, no crop — the full camera frame
//   (`.resizeAspect`) in a rounded rectangle sized to the camera's aspect ratio (MirrorWidgetLayout).
struct MirrorWidgetView: View {

    // MARK: - Mode enum

    enum Mode: Equatable, Hashable {
        case active
        case inactive
    }

    // MARK: - State

    @State private var mode: Mode = .inactive
    @State private var session: AVCaptureSession?
    @State private var authorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var layout = MirrorWidgetLayout.shared

    @StoredSetting(.mirrorWidgetSettings) private var settings
    @StoredSetting(.mirrorCameraInputWhenAvail) private var mirrored

    private static let sessionKey = "mirrorWidget"

    private var hasCamera: Bool { CameraManager.shared.selectedDevice != nil }

    private var videoShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NookWidgetMetrics.cornerRadius, style: .continuous)
    }

    // MARK: - mirrorPlaceholderFill

    // restyle: the inactive mirror is a dark rounded rectangle (quaternary fill with
    //   a hairline edge, like the other widget cards) at the camera's aspect ratio with the
    //   web.camera symbol and "Camera"; clicking starts the live preview in the same rectangle.
    var mirrorPlaceholderFill: some View {
        videoShape
            .fill(.quaternary)
            .overlay(videoShape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }

    // MARK: - body

    var body: some View {
        GeometryReader { proxy in
            let video = layout.videoSize(in: proxy.size)
            ZStack {
                mirrorPlaceholderFill

                if mode == .active {
                    if let session {
                        MirrorPreviewView(session: session, mirrored: mirrored)
                            .clipShape(videoShape)
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else {
                    inactiveContent
                }

                if settings.showFrame {
                    videoShape.strokeBorder(.primary.opacity(0.15), lineWidth: 1)
                }
            }
            .frame(width: video.width, height: video.height)
            .contentShape(videoShape)
            .onTapGesture { toggleCamera() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Camera"))
            .accessibilityValue(mode == .active ? Text("On") : Text("Off"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleCamera() }
            .help(mode == .active ? Text("Click to stop the camera") : Text("Click to start the camera"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
        .animation(.easeInOut(duration: 0.25), value: session == nil)
        .animation(.easeInOut(duration: 0.25), value: layout.aspect)
        .nookWidgetGalleryHook()
        .onAppear {
            #if DEBUG
            MirrorWidgetDebug.install()
            #endif
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
            if mode == .inactive { refreshPlaceholderAspect() }
            if settings.autoOpen && authorization == .authorized && hasCamera {
                startCamera()
            }
        }
        .onChange(of: CameraManager.shared.selectedDevice?.uniqueID) {
            if mode == .inactive { refreshPlaceholderAspect() }
        }
        .onDisappear {
            if mode == .active || session != nil {
                mode = .inactive
                session = nil
                stopCamera()
            }
        }
    }

    /// Before the session runs: the selected camera's current active format.
    private func refreshPlaceholderAspect() {
        if let device = CameraManager.shared.selectedDevice {
            layout.update(MirrorWidgetLayout.aspect(of: device))
        }
    }

    @ViewBuilder
    private var inactiveContent: some View {
        VStack(spacing: 4) {
            if !hasCamera {
                Image(systemName: "video.slash")
                    .font(.title2)
                Text("No camera")
                    .font(.caption.weight(.medium))
            } else if authorization == .denied || authorization == .restricted {
                Image(systemName: "video.slash")
                    .font(.title2)
                Text("Camera access denied")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("Click to open System Settings")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "web.camera")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                Text("Camera")
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .padding(12)
    }

    // MARK: - Camera control

    // Dispatches on global queue with .userInitiated QoS
    // also reads the capture format the running session settled on (on the
    //   CameraManager session queue) so the video area matches the real aspect ratio.
    func setupCamera(_ completion: @escaping (AVCaptureSession?) -> Void) {
        let deviceID = CameraManager.shared.selectedDevice?.uniqueID ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
            CameraManager.shared.setupSession(for: Self.sessionKey, deviceID: deviceID)
            let session = CameraManager.shared.sessions[Self.sessionKey]?.session
            let dims = CameraManager.shared.videoDimensions(for: Self.sessionKey)
            DispatchQueue.main.async {
                if let dims { MirrorWidgetLayout.shared.update(MirrorWidgetLayout.aspect(of: dims)) }
                completion(session)
            }
        }
    }

    // Same DispatchWorkItem pattern as setupCamera
    func stopCamera() {
        DispatchQueue.global(qos: .userInitiated).async {
            CameraManager.shared.stopRunning(for: Self.sessionKey)
        }
    }

    private func startCamera() {
        mode = .active
        setupCamera { newSession in
            // the widget may have been closed or toggled off meanwhile
            guard mode == .active else {
                stopCamera()
                return
            }
            session = newSession
            if newSession == nil { mode = .inactive }
        }
    }

    // Toggles between active and inactive modes
    func toggleCamera() {
        if mode == .active {
            mode = .inactive
            session = nil
            stopCamera()
            return
        }
        guard hasCamera else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    authorization = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted { startCamera() }
                }
            }
        default:
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Preview

/// Preview layer host that attaches the session once (CameraPreview adds a new
///   preview layer on every SwiftUI update).
private struct MirrorPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        view.mirrored = mirrored
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        nsView.mirrored = mirrored
    }

    final class PreviewNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var mirrored: Bool = true {
            didSet { applyMirroring() }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            // 2026-10-20: show the whole frame (no crop); the view itself has the
            //   camera's aspect ratio, so there are no bars except during a format change
            previewLayer.videoGravity = .resizeAspect
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
            applyMirroring()
        }

        private func applyMirroring() {
            guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirrored != mirrored {
                connection.isVideoMirrored = mirrored
            }
        }
    }
}

// MARK: - DEBUG snapshots

#if DEBUG
/// DEBUG: `mirrorpreview:<dir>` (DebugHooks notification, after the Nook has been opened once)
///   writes <dir>/mirror-<aspect>-<width>.png — the inactive Mirror widget at 16:9 and 4:3, each in
///   its preferred cell width (`MirrorWidgetLayout.preferredCellWidth`) and in the current grid
///   width (`NookWidgetLayout.width(of: .mirror)`), black background, 202 pt row. The camera is not
///   started (the live preview layer is not captured by cacheDisplay anyway).
@MainActor
enum MirrorWidgetDebug {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: DebugHooks.notificationName, object: nil, queue: .main
        ) { note in
            guard let command = note.object as? String, command.hasPrefix("mirrorpreview:") else { return }
            let dir = String(command.dropFirst("mirrorpreview:".count))
            MainActor.assumeIsolated { render(to: URL(fileURLWithPath: dir)) }
        }
    }

    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previousGlass = NookGlass.forceFallback
        NookGlass.forceFallback = true
        let layout = MirrorWidgetLayout.shared
        let previousAspect = layout.aspect
        defer {
            NookGlass.forceFallback = previousGlass
            layout.update(previousAspect)
        }
        for (name, aspect) in [("16x9", 16.0 / 9.0), ("4x3", 4.0 / 3.0)] {
            layout.update(aspect)
            NSLog("[MirrorWidgetDebug] %@: preferred cell width %.0f pt = %.2f cells", name,
                  layout.preferredCellWidth(), layout.preferredCells())
            for width in [layout.preferredCellWidth(), NookWidgetLayout.width(of: .mirror)] {
                let view = MirrorWidgetView()
                    .frame(width: width, height: MirrorWidgetLayout.rowHeight)
                    .padding(12)
                    .background(Color.black)
                    .environment(\.colorScheme, .dark)
                let size = CGSize(width: width + 24, height: MirrorWidgetLayout.rowHeight + 24)
                NookWidgetSnapshot.writePNG(view, dark: true, size: size,
                                            to: dir.appendingPathComponent("mirror-\(name)-\(Int(width)).png"),
                                            tag: "[MirrorWidgetDebug]", settle: 0.4)
            }
        }
    }
}
#endif

import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation
import Observation
import AVFoundation
import AppKit

// MARK: - CameraManager

// Manages AVCaptureSession instances per camera source identifier
@Observable
class CameraManager {
    // shared instance used by MirrorWidgetView
    static let shared = CameraManager()


    // MARK: - Stored state (observed through the accessors below)

    // video capture devices (getCaptureDeviceList())
    private var _allDevices: [AVCaptureDevice] = []

    // the device chosen for the Mirror widget (initially the saved defaultMirrorDevice, else the first)
    private var _selectedDevice: AVCaptureDevice? = nil

    // one capture session + video output per source key
    private var _sessions: [String: (session: AVCaptureSession, output: AVCaptureVideoDataOutput)] = [:]

    // all session setup/teardown and every `_sessions` mutation run on this serial
    //   queue: with concurrent callers, a quick open/close of the Mirror widget would mutate the
    //   dictionary and reconfigure the same AVCaptureSession from two threads at once.
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "DynamicNotch.CameraManager.sessions",
                                                                 qos: .userInitiated)
    @ObservationIgnored private let sessionQueueKey = DispatchSpecificKey<Void>()

    /// Runs `body` on `sessionQueue` (synchronously; re-entrant when already on it).
    private func onSessionQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil { return body() }
        return sessionQueue.sync(execute: body)
    }

    // MARK: - Observed properties

    var allDevices: [AVCaptureDevice] {
        get {
            access(keyPath: \.self._allDevices)
            return _allDevices
        }
        set {
            withMutation(keyPath: \.self._allDevices) {
                _allDevices = newValue
            }
        }
    }

    // setter: notifies observers only when the device changes
    var selectedDevice: AVCaptureDevice? {
        get {
            access(keyPath: \.self._selectedDevice)
            return _selectedDevice
        }
        set {
            let oldValue = _selectedDevice
            if oldValue == nil && newValue == nil {
                _selectedDevice = newValue
            } else if let old = oldValue, let new = newValue {
                if (old as AnyObject) === (new as AnyObject) {
                    _selectedDevice = newValue
                } else {
                    withMutation(keyPath: \.self._selectedDevice) {
                        _selectedDevice = newValue
                    }
                }
            } else {
                withMutation(keyPath: \.self._selectedDevice) {
                    _selectedDevice = newValue
                }
            }
        }
    }

    // Sessions dict: [String: (session: AVCaptureSession, output: AVCaptureVideoDataOutput)]
    var sessions: [String: (session: AVCaptureSession, output: AVCaptureVideoDataOutput)] {
        access(keyPath: \.self._sessions)
        return onSessionQueue { _sessions } // read under the session queue
    }

    // MARK: - Persisting the selection

    // Saves the selected device's uniqueID as defaultMirrorDevice (empty string when none).
    private func _selectedDeviceDidSet() {
        access(keyPath: \.self._selectedDevice)

        if let device = _selectedDevice {
            let uniqueID = device.uniqueID
            SettingsStore[.defaultMirrorDevice] = uniqueID  // key declared in Ext-D.swift
        } else {
            SettingsStore[.defaultMirrorDevice] = ""
        }
    }

    // MARK: - Init

    // Lists the capture devices and selects the saved defaultMirrorDevice, else the first device
    //   (nil when there is none).
    init() {
        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
        _allDevices = []
        _sessions = [:]

        let devices = getCaptureDeviceList()
        _allDevices = devices

        let defaultDeviceID: String = SettingsStore[.defaultMirrorDevice]

        if devices.isEmpty {
            _selectedDevice = nil
        } else {
            var foundDevice: AVCaptureDevice?
            for device in devices {
                let deviceID = device.uniqueID
                if deviceID == defaultDeviceID {
                    foundDevice = device
                    break
                }
            }

            if let found = foundDevice {
                _selectedDevice = found
            } else {
                _selectedDevice = devices[0]
            }
        }
    }

    // MARK: - captureSession(for:)

    // The session for `key`, created (with its video output) on first use.
    func captureSession(for key: String) -> AVCaptureSession {
        onSessionQueue { captureSessionLocked(for: key) }
    }

    private func captureSessionLocked(for key: String) -> AVCaptureSession {
        access(keyPath: \.self._sessions)

        if let existing = _sessions[key] {
            return existing.session
        }

        // Create new AVCaptureSession + AVCaptureVideoDataOutput
        let newSession = AVCaptureSession()
        let newOutput = AVCaptureVideoDataOutput()

        access(keyPath: \.self._sessions)
        _sessions[key] = (session: newSession, output: newOutput)

        return newSession
    }

    // MARK: - setupSession(for:, deviceID:)

    // Finds device from allDevices by uniqueID; if found:
    //   - Gets or creates AVCaptureSession + output for the key
    //   - beginConfiguration → removeInputs → removeOutputs
    //   - Create AVCaptureDeviceInput with device; if canAddInput → addInput
    //   - If canAddOutput → addOutput
    //   - Set videoMirrored from UserDefaults.mirrorCameraInputWhenAvail
    //   - commitConfiguration
    //   - Store the pair back in the sessions dict
    //   - If session not running → startRunning
    func setupSession(for key: String, deviceID: String) {
        onSessionQueue { setupSessionLocked(for: key, deviceID: deviceID) }
    }

    private func setupSessionLocked(for key: String, deviceID: String) {
        // Access allDevices
        access(keyPath: \.self._allDevices)

        // Iterate allDevices looking for matching uniqueID
        guard let device = _allDevices.first(where: { $0.uniqueID == deviceID }) else {
            return
        }

        // Get or create session + output
        let session = captureSessionLocked(for: key)

        // beginConfiguration
        session.beginConfiguration()

        // Remove existing inputs
        for input in session.inputs {
            session.removeInput(input)
        }

        // Remove existing outputs
        for output in session.outputs {
            session.removeOutput(output)
        }

        // Create AVCaptureDeviceInput from device
        if let deviceInput = try? AVCaptureDeviceInput(device: device) {
            // canAddInput check
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
            }
        } else {
                print("CameraManager.setupSession: failed to create device input for \(key)")
        }

        // Get existing output from sessions dict
        access(keyPath: \.self._sessions)
        let existingOutput = _sessions[key]?.output

        if let output = existingOutput {
            // canAddOutput check
            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            // Get video connection and set mirrored from UserDefaults
            if let connection = output.connection(with: .video) {
                let mirrored: Bool = SettingsStore[.mirrorCameraInputWhenAvail]
                if connection.isVideoMirroringSupported {  // required before setting isVideoMirrored
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirrored
                }
            }
        }

        // commitConfiguration
        session.commitConfiguration()

        // store the pair back in the sessions dict
        if let output = existingOutput {
            access(keyPath: \.self._sessions)
            _sessions[key] = (session: session, output: output)
        }

        // Start running if not already running
        if !session.isRunning {
            session.startRunning()
        }
    }

    // MARK: - stopRunning(for:)

    // Looks up session in _sessions dict; if found:
    //   - If isRunning: beginConfiguration → removeInputs → removeOutputs → commitConfiguration → stopRunning
    //   - setSampleBufferDelegate(nil, nil)
    //   - Remove it from the sessions dict
    func stopRunning(for key: String) {
        onSessionQueue { stopRunningLocked(for: key) }
    }

    private func stopRunningLocked(for key: String) {
        access(keyPath: \.self._sessions)

        // Look up by key in dictionary
        guard let entry = _sessions[key] else {
            return
        }

        let session = entry.session

        // Check isRunning
        if session.isRunning {
            // beginConfiguration
            session.beginConfiguration()

            // Remove inputs
            for input in session.inputs {
                session.removeInput(input)
            }

            // Remove outputs
            for output in session.outputs {
                session.removeOutput(output)
            }

            // commitConfiguration → stopRunning
            session.commitConfiguration()
            session.stopRunning()
        }

        // Set sampleBufferDelegate to nil
        entry.output.setSampleBufferDelegate(nil, queue: nil)

        access(keyPath: \.self._sessions)
        _sessions.removeValue(forKey: key)
    }
}

// MARK: - Video format (Mirror widget sizing)

// 2026-10-20: the Mirror widget shows the whole camera frame (no crop) and sizes
//   its video area to the camera's aspect ratio, so it needs the format's pixel dimensions.
extension CameraManager {
    /// Pixel dimensions of `device`'s active format (nil when the format reports 0×0).
    static func videoDimensions(of device: AVCaptureDevice) -> CMVideoDimensions? {
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return dims.width > 0 && dims.height > 0 ? dims : nil
    }

    /// Dimensions of the format the session for `key` is actually capturing with (read on the
    ///   serialized session queue, after `setupSession` committed the configuration and started the
    ///   session, which is when the session preset has picked the device's active format).
    func videoDimensions(for key: String) -> CMVideoDimensions? {
        onSessionQueue {
            guard let session = _sessions[key]?.session else { return nil }
            let device = session.inputs.lazy.compactMap { ($0 as? AVCaptureDeviceInput)?.device }.first
            return device.flatMap(Self.videoDimensions(of:))
        }
    }
}

// MARK: - Free function: getCaptureDeviceList

// Uses AVCaptureDevice.DiscoverySession to enumerate video devices
private func getCaptureDeviceList() -> [AVCaptureDevice] {
    // DiscoverySession for built-in wide-angle camera + external cameras
    let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external],
        mediaType: .video,
        position: .unspecified
    )
    return discoverySession.devices
}

import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import CoreAudio
import Observation

// MARK: - VolumeMonitor

// CoreAudio-based system volume monitor
// Uses AudioObjectPropertyAddress (kAudioDevicePropertyVolumeScalar etc.)
@Observable
class VolumeMonitor {

    // MARK: - Stored properties

    var volume: CGFloat = 0

    var monitoredDeviceID: UInt32 = 0

    private var volumeListenerBlock: ((UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void)?

    private var defaultDeviceListenerBlock: ((UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void)?

    // the exact CoreAudio blocks registered, needed to remove them again
    private var registeredDefaultDeviceBlock: AudioObjectPropertyListenerBlock?
    private var registeredVolumeBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Singletons

    static let shared: VolumeMonitor = {
        let monitor = VolumeMonitor()
        monitor.volume = 0
        monitor.monitoredDeviceID = 0
        monitor.volumeListenerBlock = nil
        monitor.defaultDeviceListenerBlock = nil
        monitor.setupVolumeMonitoring()
        return monitor
    }()

    private init() {}


    // Listens for default-output-device changes (rebinding the volume listener), then binds the
    // volume listener to the current default output device and reads the initial volume.
    func setupVolumeMonitoring() {
        // Default device change listener
        let listenerBlock: (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void = { [weak self] deviceID, address in
            /* Device changed → rebind volume listener */
            // rebind to the new default output device (CoreAudio passes no device ID)
            guard let self else { return }
            self.unbindVolumeListener()
            if let newID = self.getDefaultOutputDeviceID() { self.bindVolumeListener(to: newID) }
            self.updateVolume()
        }

        defaultDeviceListenerBlock = listenerBlock

        // Register listener on kAudioObjectSystemObject (1)
        // kAudioHardwarePropertyDefaultOutputDevice
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // queue: main; block stored for removal
        let caBlock: AudioObjectPropertyListenerBlock = { [weak self] inNumAddresses, inAddresses in
            self?.defaultDeviceListenerBlock?(inNumAddresses, inAddresses)
        }
        registeredDefaultDeviceBlock = caBlock
        AudioObjectAddPropertyListenerBlock(
            1,  // kAudioObjectSystemObject
            &address,
            DispatchQueue.main,
            caBlock
        )

        // Get current default output device ID
        if let deviceID = getDefaultOutputDeviceID() {
            // Bind volume listener
            bindVolumeListener(to: deviceID)
            // Read initial volume
            updateVolume()
        }
    }


    // Listens for kAudioDevicePropertyVolumeScalar changes on `deviceID`.
    func bindVolumeListener(to deviceID: UInt32) {
        // Store device ID
        monitoredDeviceID = deviceID

        // Volume listener block
        let listenerBlock: (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void = { [weak self] deviceID, address in
            self?.updateVolume()
        }

        volumeListenerBlock = listenerBlock

        // kAudioDevicePropertyVolumeScalar address
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Add listener on the specified device
        // queue: main; block stored for removal
        let caBlock: AudioObjectPropertyListenerBlock = { [weak self] inNumAddresses, inAddresses in
            self?.volumeListenerBlock?(inNumAddresses, inAddresses)
        }
        registeredVolumeBlock = caBlock
        AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            DispatchQueue.main,
            caBlock
        )
    }


    // Removes the volume listener from the monitored device, if one is registered.
    func unbindVolumeListener() {
        // Only unbind if we have an active listener
        guard monitoredDeviceID != 0, volumeListenerBlock != nil else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Remove listener
        if let caBlock = registeredVolumeBlock {
            AudioObjectRemovePropertyListenerBlock(monitoredDeviceID, &address, DispatchQueue.main, caBlock)
            registeredVolumeBlock = nil
        }

        // Nullify stored listener
        volumeListenerBlock = nil
        monitoredDeviceID = 0
    }


    // Removes both CoreAudio listeners.
    func removeVolumeMonitoring() {
        // Unbind volume listener first
        unbindVolumeListener()

        // Remove default device listener if exists
        if defaultDeviceListenerBlock != nil {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            if let caBlock = registeredDefaultDeviceBlock {
                AudioObjectRemovePropertyListenerBlock(1, &address, DispatchQueue.main, caBlock)
                registeredDefaultDeviceBlock = nil
            }

            defaultDeviceListenerBlock = nil
        }
    }


    // Reads the default output device's volume scalar and publishes it when it changed (or was NaN).
    func updateVolume() {
        // Get current default output device ID
        guard let deviceID = getDefaultOutputDeviceID() else { return }

        // Read volume as Float32 (4 bytes)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var volumeValue: Float32 = 0
        var dataSize: UInt32 = 4

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &volumeValue
        )

        // Check status
        guard status == noErr else { return }

        let newVolume = CGFloat(volumeValue)

        // Update if different from current (handles NaN)
        if newVolume != volume || newVolume.isNaN != volume.isNaN {
            volume = newVolume
        }
    }

    // MARK: - Private helpers

    // Get default output device ID from CoreAudio
    private func getDefaultOutputDeviceID() -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: UInt32 = 0
        var dataSize: UInt32 = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            1,  // kAudioObjectSystemObject
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return nil }
        return deviceID
    }
}

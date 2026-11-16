import Foundation
import CoreAudio
import AudioToolbox
import Combine

/// Reads and writes the default output device volume (hardware / Core Audio), not app-specific volume.
@MainActor
final class SystemVolumeService: ObservableObject {
    @Published private(set) var volume: Float = 0.5
    @Published private(set) var isMuted: Bool = false

    private var deviceID: AudioDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceChangeBlock: AudioObjectPropertyListenerBlock?

    init() {
        refreshDevice()
        refresh()
        installListeners()
        observeDefaultDevice()
    }

    deinit {
        // Listeners use DispatchQueue.main blocks; tear down without hopping to MainActor.
        Self.removeListeners(deviceID: deviceID, volumeBlock: volumeListenerBlock, muteBlock: muteListenerBlock)
        if let deviceChangeBlock {
            var address = Self.defaultDeviceAddress()
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, deviceChangeBlock)
        }
    }

    func setVolume(_ value: Float) {
        let clamped = Self.clamp(value)
        guard deviceID != kAudioObjectUnknown else { return }

        var vol = clamped
        var address = Self.volumeAddress()
        var status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &vol)
        if status != noErr {
            status = setChannelVolumes(clamped)
        }
        if status != noErr {
            Log.volume.error("setVolume failed: \(status)")
            return
        }
        volume = clamped
        if clamped > 0, isMuted {
            setMuted(false)
        }
        Log.volume.debug("Volume set to \(clamped, format: .fixed(precision: 2))")
    }

    func setMuted(_ muted: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        var value: UInt32 = muted ? 1 : 0
        var address = Self.muteAddress()
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
        if status != noErr {
            Log.volume.error("setMuted failed: \(status)")
            return
        }
        isMuted = muted
        Log.volume.debug("Mute set to \(muted)")
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func refresh() {
        refreshDevice()
        volume = readVolume() ?? volume
        isMuted = readMute() ?? isMuted
    }

    nonisolated static func clamp(_ value: Float) -> Float {
        min(1, max(0, value))
    }

    // MARK: - Core Audio

    private func setChannelVolumes(_ value: Float) -> OSStatus {
        var result: OSStatus = kAudioHardwareUnknownPropertyError
        for element: UInt32 in [1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var vol = value
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &vol) == noErr {
                result = noErr
            }
        }
        return result
    }

    private func observeDefaultDevice() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.removeListeners()
                self.refresh()
                self.installListeners()
            }
        }
        deviceChangeBlock = block
        var address = Self.defaultDeviceAddress()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    private func refreshDevice() {
        var address = Self.defaultDeviceAddress()
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        if status == noErr {
            deviceID = device
        } else {
            Log.volume.error("Could not get default output device: \(status)")
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func readVolume() -> Float? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        var address = Self.volumeAddress()
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            // Some devices expose volume only on channels; try left channel as fallback.
            return readChannelVolume(element: 1)
        }
        return Self.clamp(value)
    }

    private func readChannelVolume(element: UInt32) -> Float? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            Log.volume.error("readVolume failed: \(status)")
            return nil
        }
        return Self.clamp(value)
    }

    private func readMute() -> Bool? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        var address = Self.muteAddress()
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value != 0
    }

    private func installListeners() {
        removeListeners()
        guard deviceID != kAudioObjectUnknown else { return }

        let volumeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        volumeListenerBlock = volumeBlock
        muteListenerBlock = muteBlock

        var volumeAddress = Self.volumeAddress()
        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, volumeBlock)

        var muteAddress = Self.muteAddress()
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, muteBlock)
    }

    private func removeListeners() {
        Self.removeListeners(deviceID: deviceID, volumeBlock: volumeListenerBlock, muteBlock: muteListenerBlock)
        volumeListenerBlock = nil
        muteListenerBlock = nil
    }

    nonisolated private static func removeListeners(
        deviceID: AudioDeviceID,
        volumeBlock: AudioObjectPropertyListenerBlock?,
        muteBlock: AudioObjectPropertyListenerBlock?
    ) {
        guard deviceID != kAudioObjectUnknown else { return }
        if let volumeBlock {
            var address = volumeAddress()
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, volumeBlock)
        }
        if let muteBlock {
            var address = muteAddress()
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, muteBlock)
        }
    }

    nonisolated private static func defaultDeviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// The virtual main volume is what the menu bar / volume keys drive; unlike the
    /// main-element scalar it exists on built-in, Bluetooth and USB outputs alike.
    nonisolated private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

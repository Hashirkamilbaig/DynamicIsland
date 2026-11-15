import Foundation
import CoreAudio
import Combine

/// Reads and writes the default output device volume (hardware / Core Audio), not app-specific volume.
@MainActor
final class SystemVolumeService: ObservableObject {
    @Published private(set) var volume: Float = 0.5
    @Published private(set) var isMuted: Bool = false

    private var deviceID: AudioDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refreshDevice()
        refresh()
        installListeners()
    }

    deinit {
        // Listeners use DispatchQueue.main blocks; tear down without hopping to MainActor.
        Self.removeListeners(deviceID: deviceID, volumeBlock: volumeListenerBlock, muteBlock: muteListenerBlock)
    }

    func setVolume(_ value: Float) {
        let clamped = Self.clamp(value)
        guard deviceID != kAudioObjectUnknown else { return }

        var vol = clamped
        var address = Self.volumeAddress()
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float>.size),
            &vol
        )
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

    private func refreshDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
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

    nonisolated private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
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

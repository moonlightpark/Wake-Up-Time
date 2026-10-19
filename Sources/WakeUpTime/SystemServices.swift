import AudioToolbox
import CoreAudio
import Foundation
import IOKit.pwr_mgt

/// Reads and writes the default output device's volume and mute state.
enum SystemAudio {
    private static func defaultOutputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static var volume: Float? {
        get {
            guard let device = defaultOutputDevice() else { return nil }
            var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
            return value
        }
        set {
            guard let device = defaultOutputDevice(), var value = newValue else { return }
            var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    static var isMuted: Bool? {
        get {
            guard let device = defaultOutputDevice() else { return nil }
            var addr = address(kAudioDevicePropertyMute)
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
            return value != 0
        }
        set {
            guard let device = defaultOutputDevice(), let newValue else { return }
            var addr = address(kAudioDevicePropertyMute)
            var value = UInt32(newValue ? 1 : 0)
            AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}

/// Power management. The original app relied on a privileged helper to sleep and wake
/// the Mac; this version keeps the system awake while an alarm is set and only turns
/// the display off, which needs no extra privileges.
enum Power {
    private static var systemAssertion: IOPMAssertionID = 0
    private static var displayAssertion: IOPMAssertionID = 0
    private static var activityAssertion: IOPMAssertionID = 0

    static func keepSystemAwake(_ on: Bool) {
        toggle(&systemAssertion, on: on, type: "PreventUserIdleSystemSleep",
               reason: "Wake Up Time alarm is set")
    }

    static func keepDisplayAwake(_ on: Bool) {
        toggle(&displayAssertion, on: on, type: "PreventUserIdleDisplaySleep",
               reason: "Wake Up Time full screen clock")
    }

    /// Turns the display back on, e.g. when the alarm starts.
    static func wakeDisplay() {
        IOPMAssertionDeclareUserActivity("Wake Up Time alarm" as CFString, kIOPMUserActiveLocal, &activityAssertion)
    }

    static func sleepDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    private static func toggle(_ id: inout IOPMAssertionID, on: Bool, type: String, reason: String) {
        if on, id == 0 {
            IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        reason as CFString, &id)
        } else if !on, id != 0 {
            IOPMAssertionRelease(id)
            id = 0
        }
    }
}

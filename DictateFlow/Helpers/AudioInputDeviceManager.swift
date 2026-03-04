import Foundation
import CoreAudio

enum AudioInputDeviceManager {
    enum AudioInputError: LocalizedError {
        case queryFailed(OSStatus)
        case setDefaultFailed(OSStatus)
        case deviceNotFound(String)

        var errorDescription: String? {
            switch self {
            case let .queryFailed(status):
                return "Audio-Eingabegeräte konnten nicht abgefragt werden (OSStatus: \(status))."
            case let .setDefaultFailed(status):
                return "Standard-Mikrofon konnte nicht umgestellt werden (OSStatus: \(status))."
            case let .deviceNotFound(uid):
                return "Gewähltes Mikrofon wurde nicht gefunden: \(uid)"
            }
        }
    }

    static func availableInputDevices() -> [AudioInputDevice] {
        allAudioDeviceIDs()
            .filter(hasInputStreams)
            .compactMap { deviceID in
                guard
                    let uid = deviceUID(for: deviceID),
                    let name = deviceName(for: deviceID)
                else {
                    return nil
                }

                return AudioInputDevice(
                    id: uid,
                    name: name,
                    deviceID: deviceID
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    static func containsDevice(uid: String) -> Bool {
        !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            availableInputDevices().contains(where: { $0.id == uid })
    }

    static func deviceID(forUID uid: String) -> UInt32? {
        availableInputDevices().first(where: { $0.id == uid })?.deviceID
    }

    static func defaultInputDeviceID() throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            throw AudioInputError.queryFailed(status)
        }

        return deviceID
    }

    static func setDefaultInputDevice(id: UInt32) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableID = AudioDeviceID(id)
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            dataSize,
            &mutableID
        )

        guard status == noErr else {
            throw AudioInputError.setDefaultFailed(status)
        }
    }

    private static func allAudioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

        let readStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard readStatus == noErr else {
            return []
        }

        return deviceIDs
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        stringProperty(
            selector: kAudioObjectPropertyName,
            for: deviceID
        )
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        stringProperty(
            selector: kAudioDevicePropertyDeviceUID,
            for: deviceID
        )
    }

    private static func stringProperty(
        selector: AudioObjectPropertySelector,
        for deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var unmanagedCFString: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &unmanagedCFString
        )

        guard status == noErr, let unmanagedCFString else {
            return nil
        }

        let swiftString = unmanagedCFString.takeRetainedValue() as String
        return swiftString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : swiftString
    }
}

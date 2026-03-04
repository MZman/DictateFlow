import Foundation
import Carbon

final class HotkeyManager {
    enum HotkeyError: LocalizedError {
        case registrationFailed(String)

        var errorDescription: String? {
            switch self {
            case let .registrationFailed(message):
                return message
            }
        }
    }

    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    deinit {
        unregister()
    }

    func registerDefaultShortcut() throws {
        try register(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey) | UInt32(shiftKey))
    }

    func register(keyCode: UInt32, modifiers: UInt32) throws {
        unregister()

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onHotKeyPressed?()
            }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventSpec,
            selfPointer,
            &handlerRef
        )

        guard installStatus == noErr else {
            throw HotkeyError.registrationFailed("InstallEventHandler fehlgeschlagen (\(installStatus)).")
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x44465446), id: 1) // DFTF

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            throw HotkeyError.registrationFailed("RegisterEventHotKey fehlgeschlagen (\(registerStatus)).")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}

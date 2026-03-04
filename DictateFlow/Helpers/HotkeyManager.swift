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
    var onHotKeyReleased: (() -> Void)?

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

        var eventSpecs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData else { return noErr }
            guard let eventRef else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let eventKind = GetEventKind(eventRef)
            DispatchQueue.main.async {
                switch eventKind {
                case UInt32(kEventHotKeyPressed):
                    manager.onHotKeyPressed?()
                case UInt32(kEventHotKeyReleased):
                    manager.onHotKeyReleased?()
                default:
                    break
                }
            }
            return noErr
        }

        let installStatus = eventSpecs.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            return InstallEventHandler(
                GetEventDispatcherTarget(),
                callback,
                buffer.count,
                baseAddress,
                selfPointer,
                &handlerRef
            )
        }

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

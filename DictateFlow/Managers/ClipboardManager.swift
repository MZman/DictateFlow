import Foundation
import AppKit
import ApplicationServices
import Carbon

final class ClipboardManager {
    enum ClipboardError: LocalizedError {
        case accessibilityPermissionMissing
        case eventSourceCreationFailed
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing:
                return "Bedienungshilfen-Berechtigung fehlt. Text wurde trotzdem in die Zwischenablage kopiert."
            case .eventSourceCreationFailed:
                return "Tastatur-Eventquelle konnte nicht erzeugt werden."
            case .eventCreationFailed:
                return "CMD+V konnte nicht simuliert werden."
            }
        }
    }

    func copy(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func copyAndPaste(text: String, promptForAccessibility: Bool = true) throws {
        copy(text: text)

        guard requestAccessibilityPermission(prompt: promptForAccessibility) else {
            throw ClipboardError.accessibilityPermissionMissing
        }

        try simulatePaste()
    }

    private func simulatePaste() throws {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            throw ClipboardError.eventSourceCreationFailed
        }

        guard
            let keyDown = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
        else {
            throw ClipboardError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

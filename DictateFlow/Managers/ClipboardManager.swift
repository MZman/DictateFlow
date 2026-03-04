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

    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestAccessibilityPermissionAndWait(
        prompt: Bool = true,
        timeout: TimeInterval = 20,
        pollInterval: TimeInterval = 0.4
    ) async -> Bool {
        if hasAccessibilityPermission() {
            return true
        }

        _ = requestAccessibilityPermission(prompt: prompt)

        guard timeout > 0 else {
            return hasAccessibilityPermission()
        }

        let deadline = Date().addingTimeInterval(timeout)
        let safeInterval = max(0.1, pollInterval)
        while Date() < deadline {
            if hasAccessibilityPermission() {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(safeInterval * 1_000_000_000))
        }

        return hasAccessibilityPermission()
    }

    func accessibilityTroubleshootingHint() -> String {
        let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "DictateFlow"
        let executablePath = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments.first ?? "unbekannt"
        let isXcodeDerivedDataBuild = executablePath.contains("/Library/Developer/Xcode/DerivedData/") || executablePath.contains("/DerivedData/")

        let xcodeHint: String
        if isXcodeDerivedDataBuild {
            xcodeHint = """

            Hinweis für Xcode-Debug-Build:
            Dieser Build läuft aus DerivedData. Bei ad-hoc-signierten Debug-Builds kann die Berechtigung nach Rebuilds ungültig werden.
            Empfehlung: In Xcode unter Signing & Capabilities ein Development Team setzen (Apple Development Signatur), danach App neu bauen, komplett neu starten und Bedienungshilfe erneut erlauben.
            Falls weiterhin blockiert: `tccutil reset Accessibility com.mesutoezciftci.DictateFlow`
            """
        } else {
            xcodeHint = ""
        }

        return """
        Bitte in Systemeinstellungen > Datenschutz & Sicherheit > Bedienungshilfen den aktiven Eintrag von \(appName) erlauben.
        Aktueller Prozesspfad: \(executablePath)
        Wenn \(appName) mehrfach gelistet ist, alte Einträge entfernen und den aktuellen Eintrag erneut aktivieren.
        \(xcodeHint)
        """
    }

    func copyAndPaste(text: String, promptForAccessibility: Bool = true) throws {
        copy(text: text)

        let trusted = hasAccessibilityPermission() || requestAccessibilityPermission(prompt: promptForAccessibility)
        guard trusted else {
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

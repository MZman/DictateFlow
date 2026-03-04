import Foundation
import CoreGraphics
import Carbon

enum AppDefaults {
    static let promptTemplate = """
Du bist ein lokaler Schreibassistent.

Stilvorgabe:
{{style_instruction}}

Profilhinweis:
{{profile_hint}}

Aufgabe:
- Formuliere den Inhalt im gewünschten Stil.
- Entferne Füllwörter und Dopplungen.
- Setze Satzzeichen korrekt.
- Erhalte die inhaltliche Bedeutung.

Transkript:
{{text}}

Gib ausschließlich den finalen Text zurück.
"""

    static let customStyleInstruction = "Formuliere klar, verständlich und im gewünschten Ton."
}

@MainActor
final class SettingsStore: ObservableObject {
    private var isSanitizingFallbackLanguages = false

    static func recommendedUserModelDirectory() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("DictateFlow", isDirectory: true)
            .appendingPathComponent("whisper-models", isDirectory: true)
            .path
    }

    private enum Keys {
        static let whisperBinaryPath = "settings.whisperBinaryPath"
        static let whisperModelDirectory = "settings.whisperModelDirectory"
        static let ollamaBinaryPath = "settings.ollamaBinaryPath"
        static let ollamaModel = "settings.ollamaModel"
        static let selectedSpeechModel = "settings.selectedSpeechModel"

        static let dictationMode = "settings.dictationMode"
        static let promptStyle = "settings.promptStyle"
        static let customStyleInstruction = "settings.customStyleInstruction"
        static let promptTemplate = "settings.promptTemplate"
        static let autoPasteEnabled = "settings.autoPasteEnabled"
        static let showFloatingOverlay = "settings.showFloatingOverlay"
        static let overlayMovable = "settings.overlayMovable"
        static let overlayOriginX = "settings.overlayOriginX"
        static let overlayOriginY = "settings.overlayOriginY"
        static let launchAtLoginEnabled = "settings.launchAtLoginEnabled"
        static let primaryTranscriptionLanguage = "settings.primaryTranscriptionLanguage"
        static let fallbackTranscriptionLanguages = "settings.fallbackTranscriptionLanguages"
        static let hotkeyKey = "settings.hotkeyKey"
        static let hotkeyUseCommand = "settings.hotkeyUseCommand"
        static let hotkeyUseShift = "settings.hotkeyUseShift"
        static let hotkeyUseOption = "settings.hotkeyUseOption"
        static let hotkeyUseControl = "settings.hotkeyUseControl"
        static let pushToTalkEnabled = "settings.pushToTalkEnabled"
        static let preferredInputDeviceUID = "settings.preferredInputDeviceUID"

        // Legacy keys
        static let legacyDefaultPrompt = "settings.defaultPrompt"
        static let legacyEnablePostProcessingByDefault = "settings.enablePostProcessingByDefault"
    }

    private let defaults: UserDefaults

    @Published var whisperBinaryPath: String {
        didSet { defaults.set(whisperBinaryPath, forKey: Keys.whisperBinaryPath) }
    }

    @Published var whisperModelDirectory: String {
        didSet { defaults.set(whisperModelDirectory, forKey: Keys.whisperModelDirectory) }
    }

    @Published var ollamaBinaryPath: String {
        didSet { defaults.set(ollamaBinaryPath, forKey: Keys.ollamaBinaryPath) }
    }

    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Keys.ollamaModel) }
    }

    @Published var selectedSpeechModel: SpeechModelOption {
        didSet { defaults.set(selectedSpeechModel.rawValue, forKey: Keys.selectedSpeechModel) }
    }

    @Published var dictationMode: DictationMode {
        didSet { defaults.set(dictationMode.rawValue, forKey: Keys.dictationMode) }
    }

    @Published var promptStyle: PromptStyle {
        didSet { defaults.set(promptStyle.rawValue, forKey: Keys.promptStyle) }
    }

    @Published var customStyleInstruction: String {
        didSet { defaults.set(customStyleInstruction, forKey: Keys.customStyleInstruction) }
    }

    @Published var promptTemplate: String {
        didSet { defaults.set(promptTemplate, forKey: Keys.promptTemplate) }
    }

    @Published var autoPasteEnabled: Bool {
        didSet { defaults.set(autoPasteEnabled, forKey: Keys.autoPasteEnabled) }
    }

    @Published var showFloatingOverlay: Bool {
        didSet { defaults.set(showFloatingOverlay, forKey: Keys.showFloatingOverlay) }
    }

    @Published var overlayMovable: Bool {
        didSet { defaults.set(overlayMovable, forKey: Keys.overlayMovable) }
    }

    @Published var overlayOriginX: Double? {
        didSet {
            if let overlayOriginX {
                defaults.set(overlayOriginX, forKey: Keys.overlayOriginX)
            } else {
                defaults.removeObject(forKey: Keys.overlayOriginX)
            }
        }
    }

    @Published var overlayOriginY: Double? {
        didSet {
            if let overlayOriginY {
                defaults.set(overlayOriginY, forKey: Keys.overlayOriginY)
            } else {
                defaults.removeObject(forKey: Keys.overlayOriginY)
            }
        }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }

    @Published var primaryTranscriptionLanguage: TranscriptionLanguage {
        didSet {
            defaults.set(primaryTranscriptionLanguage.rawValue, forKey: Keys.primaryTranscriptionLanguage)
            sanitizeFallbackLanguages()
        }
    }

    @Published var fallbackTranscriptionLanguages: Set<TranscriptionLanguage> {
        didSet {
            sanitizeFallbackLanguages()
            let values = fallbackTranscriptionLanguages.map(\.rawValue).sorted()
            defaults.set(values, forKey: Keys.fallbackTranscriptionLanguages)
        }
    }

    @Published var hotkeyKey: HotkeyKey {
        didSet { defaults.set(hotkeyKey.rawValue, forKey: Keys.hotkeyKey) }
    }

    @Published var hotkeyUseCommand: Bool {
        didSet { defaults.set(hotkeyUseCommand, forKey: Keys.hotkeyUseCommand) }
    }

    @Published var hotkeyUseShift: Bool {
        didSet { defaults.set(hotkeyUseShift, forKey: Keys.hotkeyUseShift) }
    }

    @Published var hotkeyUseOption: Bool {
        didSet { defaults.set(hotkeyUseOption, forKey: Keys.hotkeyUseOption) }
    }

    @Published var hotkeyUseControl: Bool {
        didSet { defaults.set(hotkeyUseControl, forKey: Keys.hotkeyUseControl) }
    }

    @Published var pushToTalkEnabled: Bool {
        didSet { defaults.set(pushToTalkEnabled, forKey: Keys.pushToTalkEnabled) }
    }

    @Published var preferredInputDeviceUID: String {
        didSet { defaults.set(preferredInputDeviceUID, forKey: Keys.preferredInputDeviceUID) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        whisperBinaryPath = defaults.string(forKey: Keys.whisperBinaryPath) ?? "/usr/local/bin/whisper-cli"
        whisperModelDirectory = defaults.string(forKey: Keys.whisperModelDirectory) ?? Self.recommendedUserModelDirectory()
        ollamaBinaryPath = defaults.string(forKey: Keys.ollamaBinaryPath) ?? "/opt/homebrew/bin/ollama"
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llama3.1"
        if let storedSpeechModel = defaults.string(forKey: Keys.selectedSpeechModel),
           let parsedSpeechModel = SpeechModelOption(rawValue: storedSpeechModel) {
            selectedSpeechModel = parsedSpeechModel
        } else {
            selectedSpeechModel = .whisperSmall
        }

        if let storedMode = defaults.string(forKey: Keys.dictationMode), let parsedMode = DictationMode(rawValue: storedMode) {
            dictationMode = parsedMode
        } else if defaults.object(forKey: Keys.legacyEnablePostProcessingByDefault) != nil {
            dictationMode = defaults.bool(forKey: Keys.legacyEnablePostProcessingByDefault) ? .aiPrompt : .plain
        } else {
            dictationMode = .plain
        }

        if let storedPromptStyle = defaults.string(forKey: Keys.promptStyle), let parsedStyle = PromptStyle(rawValue: storedPromptStyle) {
            promptStyle = parsedStyle
        } else {
            promptStyle = .professional
        }

        customStyleInstruction = defaults.string(forKey: Keys.customStyleInstruction) ?? AppDefaults.customStyleInstruction

        let legacyPrompt = defaults.string(forKey: Keys.legacyDefaultPrompt)
        promptTemplate = defaults.string(forKey: Keys.promptTemplate) ?? legacyPrompt ?? AppDefaults.promptTemplate

        autoPasteEnabled = defaults.object(forKey: Keys.autoPasteEnabled) as? Bool ?? true
        showFloatingOverlay = defaults.object(forKey: Keys.showFloatingOverlay) as? Bool ?? false
        overlayMovable = defaults.object(forKey: Keys.overlayMovable) as? Bool ?? false
        overlayOriginX = defaults.object(forKey: Keys.overlayOriginX) as? Double
        overlayOriginY = defaults.object(forKey: Keys.overlayOriginY) as? Double

        if let storedPrimaryLanguage = defaults.string(forKey: Keys.primaryTranscriptionLanguage),
           let parsedPrimaryLanguage = TranscriptionLanguage(rawValue: storedPrimaryLanguage) {
            primaryTranscriptionLanguage = parsedPrimaryLanguage
        } else {
            primaryTranscriptionLanguage = .de
        }

        if let storedFallback = defaults.array(forKey: Keys.fallbackTranscriptionLanguages) as? [String] {
            fallbackTranscriptionLanguages = Set(storedFallback.compactMap { TranscriptionLanguage(rawValue: $0) })
        } else {
            fallbackTranscriptionLanguages = []
        }

        if let storedHotkeyKey = defaults.string(forKey: Keys.hotkeyKey),
           let parsedHotkeyKey = HotkeyKey(rawValue: storedHotkeyKey) {
            hotkeyKey = parsedHotkeyKey
        } else {
            hotkeyKey = .d
        }

        hotkeyUseCommand = defaults.object(forKey: Keys.hotkeyUseCommand) as? Bool ?? true
        hotkeyUseShift = defaults.object(forKey: Keys.hotkeyUseShift) as? Bool ?? true
        hotkeyUseOption = defaults.object(forKey: Keys.hotkeyUseOption) as? Bool ?? false
        hotkeyUseControl = defaults.object(forKey: Keys.hotkeyUseControl) as? Bool ?? false
        pushToTalkEnabled = defaults.object(forKey: Keys.pushToTalkEnabled) as? Bool ?? false
        preferredInputDeviceUID = defaults.string(forKey: Keys.preferredInputDeviceUID) ?? ""

        let storedLaunchPreference = defaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool
        launchAtLoginEnabled = storedLaunchPreference ?? LaunchAtLoginManager.isEnabled()

        if let resolvedPath = WhisperService.resolveWhisperBinaryPath(preferredPath: whisperBinaryPath) {
            whisperBinaryPath = resolvedPath
        }

        if let resolvedPath = OllamaService.resolveOllamaBinaryPath(preferredPath: ollamaBinaryPath) {
            ollamaBinaryPath = resolvedPath
        }

        if let resolvedModelDirectory = WhisperService.resolveWhisperModelDirectory(
            preferredDirectory: whisperModelDirectory,
            binaryPath: whisperBinaryPath
        ) {
            whisperModelDirectory = resolvedModelDirectory
        } else if whisperModelDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            whisperModelDirectory = Self.recommendedUserModelDirectory()
        }

        if whisperModelDirectory == "/usr/local/share/whisper", !Self.isDirectoryWritable(whisperModelDirectory) {
            whisperModelDirectory = Self.recommendedUserModelDirectory()
        }

        if !preferredInputDeviceUID.isEmpty, !AudioInputDeviceManager.containsDevice(uid: preferredInputDeviceUID) {
            preferredInputDeviceUID = ""
        }

        sanitizeFallbackLanguages()
    }

    func resetPromptToDefault() {
        promptTemplate = AppDefaults.promptTemplate
    }

    func resolvedPromptStyleInstruction() -> String {
        if promptStyle == .custom {
            let custom = customStyleInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            return custom.isEmpty ? AppDefaults.customStyleInstruction : custom
        }
        return promptStyle.instruction
    }

    func renderPrompt(text: String, profileHint: String) -> String {
        let styleInstruction = resolvedPromptStyleInstruction()
        let template = promptTemplate

        var rendered = template
            .replacingOccurrences(of: "{{style_instruction}}", with: styleInstruction)
            .replacingOccurrences(of: "{{profile_hint}}", with: profileHint)
            .replacingOccurrences(of: "{{text}}", with: text)

        if !template.contains("{{style_instruction}}") {
            rendered += "\n\nStilvorgabe:\n\(styleInstruction)"
        }

        if !template.contains("{{profile_hint}}") {
            rendered += "\n\nProfilhinweis:\n\(profileHint)"
        }

        if !template.contains("{{text}}") {
            rendered += "\n\nTranskript:\n\(text)"
        }

        return rendered.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var overlayOriginPoint: CGPoint? {
        guard let overlayOriginX, let overlayOriginY else { return nil }
        return CGPoint(x: overlayOriginX, y: overlayOriginY)
    }

    func setOverlayOrigin(_ point: CGPoint?) {
        overlayOriginX = point.map { Double($0.x) }
        overlayOriginY = point.map { Double($0.y) }
    }

    func hotkeyModifierMask() -> UInt32 {
        var mask: UInt32 = 0
        if hotkeyUseCommand { mask |= UInt32(cmdKey) }
        if hotkeyUseShift { mask |= UInt32(shiftKey) }
        if hotkeyUseOption { mask |= UInt32(optionKey) }
        if hotkeyUseControl { mask |= UInt32(controlKey) }
        if mask == 0 {
            mask = UInt32(cmdKey) | UInt32(shiftKey)
        }
        return mask
    }

    func hotkeyDisplayString() -> String {
        let mask = hotkeyModifierMask()
        var parts: [String] = []
        if (mask & UInt32(controlKey)) != 0 { parts.append("⌃") }
        if (mask & UInt32(optionKey)) != 0 { parts.append("⌥") }
        if (mask & UInt32(shiftKey)) != 0 { parts.append("⇧") }
        if (mask & UInt32(cmdKey)) != 0 { parts.append("⌘") }
        parts.append(hotkeyKey.displayName)
        return parts.joined()
    }

    func transcriptionLanguageCodes() -> [String] {
        var result: [String] = []
        result.append(primaryTranscriptionLanguage.rawValue)

        let fallbackSorted = fallbackTranscriptionLanguages
            .filter { $0 != .auto && $0 != primaryTranscriptionLanguage }
            .sorted { $0.displayName < $1.displayName }

        result.append(contentsOf: fallbackSorted.map(\.rawValue))

        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    func ensureAtLeastOneHotkeyModifier() {
        if !hotkeyUseCommand && !hotkeyUseShift && !hotkeyUseOption && !hotkeyUseControl {
            hotkeyUseCommand = true
        }
    }

    private func sanitizeFallbackLanguages() {
        guard !isSanitizingFallbackLanguages else { return }
        isSanitizingFallbackLanguages = true
        defer { isSanitizingFallbackLanguages = false }

        let sanitized = fallbackTranscriptionLanguages.filter {
            $0 != .auto && $0 != primaryTranscriptionLanguage
        }

        if sanitized != fallbackTranscriptionLanguages {
            fallbackTranscriptionLanguages = sanitized
        }
    }

    @discardableResult
    func autoDetectWhisperBinaryPath() -> Bool {
        guard let resolvedPath = WhisperService.resolveWhisperBinaryPath(preferredPath: whisperBinaryPath) else {
            return false
        }
        whisperBinaryPath = resolvedPath
        return true
    }

    @discardableResult
    func autoDetectWhisperModelDirectory() -> Bool {
        guard let resolvedDirectory = WhisperService.resolveWhisperModelDirectory(
            preferredDirectory: whisperModelDirectory,
            binaryPath: whisperBinaryPath
        ) else {
            return false
        }

        whisperModelDirectory = resolvedDirectory
        return true
    }

    @discardableResult
    func autoDetectOllamaBinaryPath() -> Bool {
        guard let resolvedPath = OllamaService.resolveOllamaBinaryPath(preferredPath: ollamaBinaryPath) else {
            return false
        }
        ollamaBinaryPath = resolvedPath
        return true
    }

    func ensureWritableModelDirectory() -> String {
        let preferred = whisperModelDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty, Self.isDirectoryWritable(preferred) {
            return preferred
        }

        let fallback = Self.recommendedUserModelDirectory()
        _ = Self.isDirectoryWritable(fallback)
        whisperModelDirectory = fallback
        return fallback
    }

    private static func isDirectoryWritable(_ path: String) -> Bool {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: path, isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let probeURL = directoryURL.appendingPathComponent(".write-test-\(UUID().uuidString)")
        let data = Data("ok".utf8)

        do {
            try data.write(to: probeURL, options: .atomic)
            try? fileManager.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }
}

import Foundation

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
            dictationMode = .aiPrompt
        }

        if let storedPromptStyle = defaults.string(forKey: Keys.promptStyle), let parsedStyle = PromptStyle(rawValue: storedPromptStyle) {
            promptStyle = parsedStyle
        } else {
            promptStyle = .professional
        }

        customStyleInstruction = defaults.string(forKey: Keys.customStyleInstruction) ?? AppDefaults.customStyleInstruction

        let legacyPrompt = defaults.string(forKey: Keys.legacyDefaultPrompt)
        promptTemplate = defaults.string(forKey: Keys.promptTemplate) ?? legacyPrompt ?? AppDefaults.promptTemplate

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

import Foundation

enum AppDefaults {
    static let defaultPrompt = """
Strukturiere den Text professionell, entferne Füllwörter, setze Satzzeichen, führe folgende Sprachbefehle aus: neuer Absatz, nummerierte Liste, Stichpunkte, formell.
"""
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
        static let defaultPrompt = "settings.defaultPrompt"
        static let enablePostProcessingByDefault = "settings.enablePostProcessingByDefault"
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

    @Published var defaultPrompt: String {
        didSet { defaults.set(defaultPrompt, forKey: Keys.defaultPrompt) }
    }

    @Published var enablePostProcessingByDefault: Bool {
        didSet { defaults.set(enablePostProcessingByDefault, forKey: Keys.enablePostProcessingByDefault) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        whisperBinaryPath = defaults.string(forKey: Keys.whisperBinaryPath) ?? "/usr/local/bin/whisper-cli"
        whisperModelDirectory = defaults.string(forKey: Keys.whisperModelDirectory) ?? Self.recommendedUserModelDirectory()
        ollamaBinaryPath = defaults.string(forKey: Keys.ollamaBinaryPath) ?? "/opt/homebrew/bin/ollama"
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llama3.1"
        defaultPrompt = defaults.string(forKey: Keys.defaultPrompt) ?? AppDefaults.defaultPrompt

        if defaults.object(forKey: Keys.enablePostProcessingByDefault) == nil {
            enablePostProcessingByDefault = true
        } else {
            enablePostProcessingByDefault = defaults.bool(forKey: Keys.enablePostProcessingByDefault)
        }

        // Beim Start versuchen wir automatisch den echten whisper.cpp CLI-Pfad zu finden.
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

        // Legacy-Migration: alter Systempfad ohne Schreibrechte -> auf User-Pfad umstellen.
        if whisperModelDirectory == "/usr/local/share/whisper", !Self.isDirectoryWritable(whisperModelDirectory) {
            whisperModelDirectory = Self.recommendedUserModelDirectory()
        }
    }

    func resetPromptToDefault() {
        defaultPrompt = AppDefaults.defaultPrompt
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

import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny
    case base
    case small
    case medium
    case largeV3Turbo = "large-v3-turbo"
    case largeV3 = "large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .largeV3Turbo:
            return "Large v3 Turbo"
        case .largeV3:
            return "Large v3"
        default:
            return rawValue.capitalized
        }
    }

    var filename: String {
        "ggml-\(rawValue).bin"
    }

    static func recommended(languageCode: String?, preferMaximumAccuracy: Bool = false) -> WhisperModel {
        if preferMaximumAccuracy {
            return .largeV3
        }

        guard let languageCode else {
            return .small
        }

        let normalized = languageCode.lowercased()

        if normalized == "ja" || normalized == "zh" || normalized == "yue" {
            return .medium
        }

        // Für Deutsch und die meisten europäischen Sprachen ist "small" ein guter Default.
        let europeanLanguageCodes: Set<String> = [
            "de", "en", "fr", "es", "it", "pt", "nl", "sv", "no", "da", "fi",
            "pl", "cs", "sk", "hu", "ro", "bg", "hr", "sl", "sr", "lt", "lv",
            "et", "el", "ga", "mt", "is", "uk"
        ]

        if europeanLanguageCodes.contains(normalized) {
            return .small
        }

        return .base
    }
}

final class WhisperService {
    private struct ResolvedModel {
        let url: URL
        let effectiveModel: WhisperModel
    }

    enum WhisperError: LocalizedError {
        case binaryNotFound(String)
        case modelNotFound(String)
        case modelDownloadFailed(String)
        case transcriptionFailed(String)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case let .binaryNotFound(details):
                if details.hasPrefix("Kein ausführbares") {
                    return details
                }
                return "whisper.cpp CLI wurde nicht gefunden: \(details)"
            case let .modelNotFound(details):
                if details.hasPrefix("Kein passendes") {
                    return details
                }
                return "Whisper-Modell wurde nicht gefunden: \(details)"
            case let .modelDownloadFailed(details):
                return "Whisper-Modell konnte nicht geladen werden: \(details)"
            case let .transcriptionFailed(message):
                return "Whisper-Transkription fehlgeschlagen: \(message)"
            case .emptyResult:
                return "Whisper hat keinen Text zurückgegeben."
            }
        }
    }

    private static let binaryNames = [
        "whisper-cli",
        "whisper-cpp",
        "main"
    ]

    private static let commonBinaryPaths = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp",
        "/usr/local/bin/whisper-cpp",
        "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli",
        "/usr/local/opt/whisper-cpp/bin/whisper-cli"
    ]

    private static let commonModelDirectories = [
        "/opt/homebrew/share/whisper",
        "/usr/local/share/whisper",
        "/opt/homebrew/opt/whisper-cpp/share/whisper",
        "/usr/local/opt/whisper-cpp/share/whisper"
    ]

    static func resolveWhisperBinaryPath(preferredPath: String) -> String? {
        let fileManager = FileManager.default

        let sanitizedPreferredPath = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sanitizedPreferredPath.isEmpty, fileManager.isExecutableFile(atPath: sanitizedPreferredPath) {
            return sanitizedPreferredPath
        }

        for path in commonBinaryPaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }

        if let bundledPath = Bundle.main.path(forResource: "whisper-cli", ofType: nil),
           fileManager.isExecutableFile(atPath: bundledPath) {
            return bundledPath
        }

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            let searchPaths = pathEnv.split(separator: ":").map(String.init)
            for directory in searchPaths {
                for binaryName in binaryNames {
                    let candidate = (directory as NSString).appendingPathComponent(binaryName)
                    if fileManager.isExecutableFile(atPath: candidate) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    static func resolveWhisperModelDirectory(preferredDirectory: String, binaryPath: String) -> String? {
        let resolvedBinaryPath = resolveWhisperBinaryPath(preferredPath: binaryPath) ?? binaryPath
        let directories = candidateModelDirectories(
            preferredDirectory: preferredDirectory,
            binaryPath: resolvedBinaryPath
        )

        for directory in directories where hasAnyWhisperModel(in: directory) {
            return directory
        }

        return nil
    }

    func transcribe(
        audioURL: URL,
        model: WhisperModel,
        binaryPath: String,
        modelDirectory: String,
        languageCodes: [String] = ["de"]
    ) async throws -> String {
        guard let resolvedBinaryPath = Self.resolveWhisperBinaryPath(preferredPath: binaryPath) else {
            let triedPaths = ([binaryPath] + Self.commonBinaryPaths).joined(separator: ", ")
            throw WhisperError.binaryNotFound(
                "Kein ausführbares whisper.cpp CLI gefunden. Geprüft: \(triedPaths). " +
                "Installiere z. B. mit 'brew install whisper-cpp' und klicke in den Einstellungen auf 'Whisper automatisch finden'."
            )
        }

        let modelDirectories = Self.candidateModelDirectories(
            preferredDirectory: modelDirectory,
            binaryPath: resolvedBinaryPath
        )

        guard let resolvedModel = Self.resolveModel(
            requestedModel: model,
            candidateDirectories: modelDirectories
        ) else {
            let directoriesText = modelDirectories.isEmpty ? "-" : modelDirectories.joined(separator: ", ")
            let availableModels = Self.availableModelFilenames(in: modelDirectories)
            let availableText = availableModels.isEmpty ? "keine" : availableModels.joined(separator: ", ")
            throw WhisperError.modelNotFound(
                "Kein passendes Whisper-Modell gefunden. Gesucht: \(model.filename). " +
                "Durchsucht: \(directoriesText). Gefunden: \(availableText). " +
                "Lade ein Modell über das LMM-Auswahlfenster herunter oder nutze in den Einstellungen 'Modellordner automatisch finden'."
            )
        }

        if resolvedModel.effectiveModel != model {
            NSLog(
                "DictateFlow: Modell '%@' nicht gefunden, verwende '%@' (%@).",
                model.rawValue,
                resolvedModel.effectiveModel.rawValue,
                resolvedModel.url.path
            )
        }

        let sanitizedCodes = normalizedLanguageCodes(languageCodes)
        var attemptErrors: [String] = []

        for languageCode in sanitizedCodes {
            var arguments = [
                "-m", resolvedModel.url.path,
                "-f", audioURL.path,
                "--no-timestamps"
            ]

            if languageCode.lowercased() != "auto" {
                arguments += ["-l", languageCode]
            }

            let result = try await ProcessRunner.run(
                executablePath: resolvedBinaryPath,
                arguments: arguments
            )

            if result.exitCode != 0 {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = detail.isEmpty ? "Exit Code \(result.exitCode)" : detail
                attemptErrors.append("[\(languageCode)] \(reason)")
                continue
            }

            let candidate = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = cleanWhisperOutput(candidate)

            if !cleaned.isEmpty {
                return cleaned
            }

            attemptErrors.append("[\(languageCode)] Leere Ausgabe")
        }

        if attemptErrors.isEmpty {
            throw WhisperError.emptyResult
        }

        throw WhisperError.transcriptionFailed(attemptErrors.joined(separator: " | "))
    }

    private func cleanWhisperOutput(_ output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline)

        let cleanedLines = lines.compactMap { rawLine -> String? in
            var line = String(rawLine)

            if line.localizedCaseInsensitiveContains("system_info") ||
                line.localizedCaseInsensitiveContains("main:") ||
                line.localizedCaseInsensitiveContains("whisper_") {
                return nil
            }

            line = line.replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)

            return line.isEmpty ? nil : line
        }

        let joined = cleanedLines.joined(separator: " ")
        return joined
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedLanguageCodes(_ codes: [String]) -> [String] {
        let cleaned = codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        var unique: [String] = []
        var seen = Set<String>()
        for code in cleaned where seen.insert(code).inserted {
            unique.append(code)
        }

        return unique.isEmpty ? ["auto"] : unique
    }

    func downloadModel(_ model: WhisperModel, to directory: String) async throws -> URL {
        let fileManager = FileManager.default
        let targetDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetDirectory.isEmpty else {
            throw WhisperError.modelDownloadFailed("Zielordner fehlt.")
        }

        try fileManager.createDirectory(
            at: URL(fileURLWithPath: targetDirectory, isDirectory: true),
            withIntermediateDirectories: true
        )

        let outputURL = URL(fileURLWithPath: targetDirectory, isDirectory: true)
            .appendingPathComponent(model.filename)

        if fileManager.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        let sourceURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(model.filename)"
        let result = try await ProcessRunner.run(
            executablePath: "/usr/bin/env",
            arguments: ["curl", "-L", "--fail", "-o", outputURL.path, sourceURL]
        )

        guard result.exitCode == 0, fileManager.fileExists(atPath: outputURL.path) else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WhisperError.modelDownloadFailed(detail.isEmpty ? "Download fehlgeschlagen." : detail)
        }

        return outputURL
    }

    func availableModels(modelDirectory: String, binaryPath: String) -> Set<WhisperModel> {
        let modelDirectories = Self.candidateModelDirectories(
            preferredDirectory: modelDirectory,
            binaryPath: binaryPath
        )

        var available = Set<WhisperModel>()
        for model in WhisperModel.allCases {
            for directory in modelDirectories {
                if Self.modelURL(for: model, in: directory) != nil {
                    available.insert(model)
                    break
                }
            }
        }

        return available
    }

    func isModelAvailable(_ model: WhisperModel, modelDirectory: String, binaryPath: String) -> Bool {
        availableModels(modelDirectory: modelDirectory, binaryPath: binaryPath).contains(model)
    }

    private static func resolveModel(
        requestedModel: WhisperModel,
        candidateDirectories: [String]
    ) -> ResolvedModel? {
        for directory in candidateDirectories {
            if let url = modelURL(for: requestedModel, in: directory) {
                return ResolvedModel(url: url, effectiveModel: requestedModel)
            }
        }

        let preferredFallbackOrder: [WhisperModel] = [.small, .base, .medium, .largeV3Turbo, .tiny, .largeV3]
        var fallbackModels = preferredFallbackOrder.filter { $0 != requestedModel }
        fallbackModels += WhisperModel.allCases.filter { candidate in
            candidate != requestedModel && !fallbackModels.contains(candidate)
        }

        for fallbackModel in fallbackModels {
            for directory in candidateDirectories {
                if let url = modelURL(for: fallbackModel, in: directory) {
                    return ResolvedModel(url: url, effectiveModel: fallbackModel)
                }
            }
        }

        return nil
    }

    private static func modelURL(for model: WhisperModel, in directory: String) -> URL? {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func candidateModelDirectories(preferredDirectory: String, binaryPath: String) -> [String] {
        let fileManager = FileManager.default
        var candidates: [String] = []

        let sanitizedPreferred = preferredDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sanitizedPreferred.isEmpty {
            candidates.append(sanitizedPreferred)
        }

        let binaryURL = URL(fileURLWithPath: binaryPath)
        let binaryDirectory = binaryURL.deletingLastPathComponent()
        let binaryParent = binaryDirectory.deletingLastPathComponent()

        candidates.append(binaryDirectory.path)
        candidates.append(binaryDirectory.appendingPathComponent("models", isDirectory: true).path)
        candidates.append(binaryParent.appendingPathComponent("share", isDirectory: true).appendingPathComponent("whisper", isDirectory: true).path)

        candidates.append(contentsOf: commonModelDirectories)

        let userHome = fileManager.homeDirectoryForCurrentUser
        candidates.append(userHome.appendingPathComponent("whisper.cpp", isDirectory: true).appendingPathComponent("models", isDirectory: true).path)
        candidates.append(userHome.appendingPathComponent("Library", isDirectory: true).appendingPathComponent("Application Support", isDirectory: true).appendingPathComponent("whisper", isDirectory: true).path)

        if let bundleResourceURL = Bundle.main.resourceURL {
            candidates.append(bundleResourceURL.appendingPathComponent("models", isDirectory: true).path)
        }

        var seen = Set<String>()
        return candidates.compactMap { rawPath in
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let standardized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            guard seen.insert(standardized).inserted else { return nil }
            return standardized
        }
    }

    private static func hasAnyWhisperModel(in directory: String) -> Bool {
        !availableModelFilenames(in: [directory]).isEmpty
    }

    private static func availableModelFilenames(in directories: [String]) -> [String] {
        let fileManager = FileManager.default
        var result = Set<String>()

        for directory in directories {
            guard let items = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for item in items where item.hasPrefix("ggml-") && item.hasSuffix(".bin") {
                result.insert(item)
            }
        }

        return result.sorted()
    }
}

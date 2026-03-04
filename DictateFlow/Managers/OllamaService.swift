import Foundation

final class OllamaService {
    static let shared = OllamaService()

    private var serverProcess: Process?
    private var serverStartedByApp = false

    private init() {}

    enum OllamaError: LocalizedError {
        case emptyModel
        case binaryNotFound(String)
        case serverStartFailed(String)
        case processFailed(String)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .emptyModel:
                return "Es wurde kein Ollama-Modell konfiguriert."
            case let .binaryNotFound(details):
                if details.hasPrefix("Kein ausführbares") {
                    return details
                }
                return "Ollama CLI wurde nicht gefunden: \(details)"
            case let .serverStartFailed(details):
                return "Ollama-Server konnte nicht gestartet werden: \(details)"
            case let .processFailed(message):
                return "Ollama-Ausführung fehlgeschlagen: \(message)"
            case .emptyResult:
                return "Ollama hat keinen Text zurückgegeben."
            }
        }
    }

    private static let binaryNames = ["ollama"]

    private static let commonBinaryPaths = [
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/Applications/Ollama.app/Contents/Resources/ollama",
        "/Applications/Ollama.app/Contents/MacOS/Ollama"
    ]

    static func resolveOllamaBinaryPath(preferredPath: String?) -> String? {
        let fileManager = FileManager.default
        let sanitizedPreferredPath = preferredPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !sanitizedPreferredPath.isEmpty, fileManager.isExecutableFile(atPath: sanitizedPreferredPath) {
            return sanitizedPreferredPath
        }

        for path in commonBinaryPaths where fileManager.isExecutableFile(atPath: path) {
            return path
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

    func ensureServerRunning(binaryPath: String?) async throws {
        guard let resolvedBinaryPath = Self.resolveOllamaBinaryPath(preferredPath: binaryPath) else {
            let checkedPath = binaryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let triedPaths = ([checkedPath] + Self.commonBinaryPaths)
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            throw OllamaError.binaryNotFound(
                "Kein ausführbares Ollama CLI gefunden. Geprüft: \(triedPaths). " +
                "Installiere Ollama und nutze in den Einstellungen 'Ollama automatisch finden'."
            )
        }

        if await probeServerRunning(binaryPath: resolvedBinaryPath) {
            if serverProcess?.isRunning != true {
                serverStartedByApp = false
            }
            return
        }

        try launchServerIfNeeded(binaryPath: resolvedBinaryPath)

        let maxAttempts = 20
        for _ in 0..<maxAttempts {
            if await probeServerRunning(binaryPath: resolvedBinaryPath) {
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }

        throw OllamaError.serverStartFailed(
            "Server antwortet nicht auf Anfragen. Starte manuell mit '\(resolvedBinaryPath) serve'."
        )
    }

    func stopServerIfManagedByApp() {
        guard serverStartedByApp else { return }
        guard let process = serverProcess else { return }

        if process.isRunning {
            process.terminate()

            let timeout = Date().addingTimeInterval(1.5)
            while process.isRunning, Date() < timeout {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }

            if process.isRunning {
                process.interrupt()
            }
        }

        serverProcess = nil
        serverStartedByApp = false
    }

    func refine(
        text: String,
        profile: Profile,
        model: String,
        basePrompt: String,
        binaryPath: String?
    ) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw OllamaError.emptyModel
        }

        guard let resolvedBinaryPath = Self.resolveOllamaBinaryPath(preferredPath: binaryPath) else {
            let checkedPath = binaryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let triedPaths = ([checkedPath] + Self.commonBinaryPaths)
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            throw OllamaError.binaryNotFound(
                "Kein ausführbares Ollama CLI gefunden. Geprüft: \(triedPaths). " +
                "Installiere Ollama und nutze in den Einstellungen 'Ollama automatisch finden'."
            )
        }

        try await ensureServerRunning(binaryPath: resolvedBinaryPath)

        let prompt = """
\(basePrompt)

Profilhinweis: \(profile.llmHint)

Text:
\(text)

Gib ausschließlich den finalen, überarbeiteten Text zurück.
"""

        let result = try await ProcessRunner.run(
            executablePath: resolvedBinaryPath,
            arguments: ["run", trimmedModel],
            input: prompt
        )

        guard result.exitCode == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw OllamaError.processFailed(detail.isEmpty ? "Exit Code \(result.exitCode)" : detail)
        }

        let cleaned = stripANSI(from: result.stdout)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            throw OllamaError.emptyResult
        }

        return cleaned
    }

    func isServerRunning(binaryPath: String?) async -> Bool {
        guard let resolvedBinaryPath = Self.resolveOllamaBinaryPath(preferredPath: binaryPath) else {
            return false
        }
        return await probeServerRunning(binaryPath: resolvedBinaryPath)
    }

    private func stripANSI(from text: String) -> String {
        text.replacingOccurrences(of: #"\u001B\[[0-9;]*m"#, with: "", options: .regularExpression)
    }

    private func probeServerRunning(binaryPath: String) async -> Bool {
        guard let result = try? await ProcessRunner.run(
            executablePath: binaryPath,
            arguments: ["list"]
        ) else {
            return false
        }

        return result.exitCode == 0
    }

    private func launchServerIfNeeded(binaryPath: String) throws {
        if let serverProcess, serverProcess.isRunning {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["serve"]

        if let devNull = FileHandle(forWritingAtPath: "/dev/null") {
            process.standardOutput = devNull
            process.standardError = devNull
        }

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.serverStartedByApp = false
            self.serverProcess = nil
        }

        do {
            try process.run()
            serverProcess = process
            serverStartedByApp = true
        } catch {
            throw OllamaError.serverStartFailed(error.localizedDescription)
        }
    }
}

import Foundation
import AppKit
import AVFoundation

enum SetupStep: Int, CaseIterable, Identifiable {
    case homebrew
    case tools
    case permissions
    case complete

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .homebrew:
            return "1. Homebrew"
        case .tools:
            return "2. Tools"
        case .permissions:
            return "3. Rechte"
        case .complete:
            return "4. Fertig"
        }
    }

    var subtitle: String {
        switch self {
        case .homebrew:
            return "Homebrew installieren und prüfen"
        case .tools:
            return "whisper.cpp und ollama einrichten"
        case .permissions:
            return "Mikrofon und Bedienungshilfen freigeben"
        case .complete:
            return "Setup abschließen"
        }
    }
}

@MainActor
final class SetupWizardViewModel: ObservableObject {
    @Published var currentStep: SetupStep = .homebrew
    @Published var isWorking = false
    @Published var statusMessage = ""
    @Published var lastErrorMessage = ""

    @Published var brewPath = ""
    @Published var isBrewInstalled = false
    @Published var isWhisperInstalled = false
    @Published var isWhisperModelAvailable = false
    @Published var isOllamaInstalled = false
    @Published var isOllamaServerRunning = false
    @Published var isMicrophoneGranted = false
    @Published var isAccessibilityGranted = false

    @Published var logLines: [String] = []

    private let settings: SettingsStore
    private let whisperService = WhisperService()
    private let ollamaService = OllamaService.shared
    private let audioRecorder = AudioRecorder()
    private let clipboardManager = ClipboardManager()

    private let brewCandidates = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var canGoBack: Bool {
        currentStep.rawValue > 0
    }

    var canGoNext: Bool {
        currentStep.rawValue < SetupStep.allCases.count - 1
    }

    var isCurrentStepSatisfied: Bool {
        switch currentStep {
        case .homebrew:
            return isBrewInstalled
        case .tools:
            return isWhisperInstalled && isWhisperModelAvailable && isOllamaInstalled && isOllamaServerRunning
        case .permissions:
            return isMicrophoneGranted && isAccessibilityGranted
        case .complete:
            return true
        }
    }

    var isSetupComplete: Bool {
        isBrewInstalled &&
            isWhisperInstalled &&
            isWhisperModelAvailable &&
            isOllamaInstalled &&
            isOllamaServerRunning &&
            isMicrophoneGranted &&
            isAccessibilityGranted
    }

    func nextStep() {
        guard canGoNext else { return }
        currentStep = SetupStep(rawValue: currentStep.rawValue + 1) ?? .complete
    }

    func previousStep() {
        guard canGoBack else { return }
        currentStep = SetupStep(rawValue: currentStep.rawValue - 1) ?? .homebrew
    }

    func refreshAll() async {
        isBrewInstalled = false
        isWhisperInstalled = false
        isWhisperModelAvailable = false
        isOllamaInstalled = false
        isOllamaServerRunning = false

        if let detectedBrewPath = await detectBrewPath() {
            brewPath = detectedBrewPath
            isBrewInstalled = true
        } else {
            brewPath = ""
        }

        if let resolvedWhisperBinary = WhisperService.resolveWhisperBinaryPath(preferredPath: settings.whisperBinaryPath) {
            settings.whisperBinaryPath = resolvedWhisperBinary
            isWhisperInstalled = true
        }

        if let resolvedModelDirectory = WhisperService.resolveWhisperModelDirectory(
            preferredDirectory: settings.whisperModelDirectory,
            binaryPath: settings.whisperBinaryPath
        ) {
            settings.whisperModelDirectory = resolvedModelDirectory
            isWhisperModelAvailable = true
        }

        if let resolvedOllamaPath = OllamaService.resolveOllamaBinaryPath(preferredPath: settings.ollamaBinaryPath) {
            settings.ollamaBinaryPath = resolvedOllamaPath
            isOllamaInstalled = true
            isOllamaServerRunning = await ollamaService.isServerRunning(binaryPath: resolvedOllamaPath)
        }

        isMicrophoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        isAccessibilityGranted = clipboardManager.requestAccessibilityPermission(prompt: false)
    }

    func installHomebrew() async {
        await runTask("Homebrew wird installiert…") {
            let installCommand = #"NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
            let result = try await ProcessRunner.run(
                executablePath: "/bin/zsh",
                arguments: ["-lc", installCommand]
            )

            guard result.exitCode == 0 else {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SetupError.commandFailed(detail.isEmpty ? "Homebrew-Installation fehlgeschlagen." : detail)
            }

            appendLog("Homebrew-Installation beendet.")
        }
    }

    func installHomebrewInTerminal() {
        let command = #"NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
        openTerminal(with: command)
        appendLog("Homebrew-Installationsbefehl im Terminal geöffnet.")
    }

    func installWhisperCpp() async {
        await runTask("whisper.cpp wird installiert…") {
            let brewPath = try await requireBrewPath()
            let result = try await ProcessRunner.run(
                executablePath: brewPath,
                arguments: ["install", "whisper-cpp"]
            )

            guard result.exitCode == 0 else {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SetupError.commandFailed(detail.isEmpty ? "Installation von whisper-cpp fehlgeschlagen." : detail)
            }

            _ = settings.autoDetectWhisperBinaryPath()
            _ = settings.autoDetectWhisperModelDirectory()
            appendLog("whisper-cpp installiert.")
        }
    }

    func installOllama() async {
        await runTask("ollama wird installiert…") {
            let brewPath = try await requireBrewPath()
            let result = try await ProcessRunner.run(
                executablePath: brewPath,
                arguments: ["install", "ollama"]
            )

            guard result.exitCode == 0 else {
                let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SetupError.commandFailed(detail.isEmpty ? "Installation von ollama fehlgeschlagen." : detail)
            }

            _ = settings.autoDetectOllamaBinaryPath()
            appendLog("ollama installiert.")
        }
    }

    func startOllamaServer() async {
        await runTask("Ollama-Server wird gestartet…") {
            try await ollamaService.ensureServerRunning(binaryPath: settings.ollamaBinaryPath)
            appendLog("Ollama-Server läuft.")
        }
    }

    func downloadRecommendedWhisperModel() async {
        await runTask("Whisper-Modell wird geladen…") {
            let targetDirectory = settings.ensureWritableModelDirectory()
            let output = try await whisperService.downloadModel(.small, to: targetDirectory)
            settings.whisperModelDirectory = output.deletingLastPathComponent().path
            appendLog("Modell geladen: \(output.lastPathComponent)")
        }
    }

    func requestMicrophonePermission() async {
        await runTask("Mikrofon-Berechtigung wird angefragt…") {
            let granted = await audioRecorder.requestPermissionIfNeeded()
            if !granted {
                openSystemSettings(anchor: "Privacy_Microphone")
                throw SetupError.permissionDenied("Mikrofon wurde nicht freigegeben.")
            }
            appendLog("Mikrofonzugriff freigegeben.")
        }
    }

    func requestAccessibilityPermission() async {
        await runTask("Bedienungshilfe-Berechtigung wird angefragt…") {
            let granted = clipboardManager.requestAccessibilityPermission(prompt: true)
            if !granted {
                openSystemSettings(anchor: "Privacy_Accessibility")
                throw SetupError.permissionDenied("Bedienungshilfe wurde nicht freigegeben.")
            }
            appendLog("Bedienungshilfe freigegeben.")
        }
    }

    func openSystemSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func runTask(_ message: String, operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = message
        lastErrorMessage = ""

        defer {
            isWorking = false
            statusMessage = ""
        }

        do {
            try await operation()
            await refreshAll()
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastErrorMessage = detail
            appendLog("Fehler: \(detail)")
            await refreshAll()
        }
    }

    private func appendLog(_ text: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        logLines.append("[\(timestamp)] \(text)")
        if logLines.count > 80 {
            logLines.removeFirst(logLines.count - 80)
        }
    }

    private func openTerminal(with command: String) {
        var escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\")
        escapedCommand = escapedCommand.replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        var scriptError: NSDictionary?
        NSAppleScript(source: scriptSource)?.executeAndReturnError(&scriptError)

        if let scriptError {
            let message = scriptError.description
            lastErrorMessage = "Terminal konnte nicht geöffnet werden: \(message)"
            appendLog("Fehler: \(lastErrorMessage)")
        }
    }

    private func requireBrewPath() async throws -> String {
        if let detected = await detectBrewPath() {
            brewPath = detected
            return detected
        }

        throw SetupError.commandFailed(
            "Homebrew wurde nicht gefunden. Bitte zuerst Homebrew installieren."
        )
    }

    private func detectBrewPath() async -> String? {
        for path in brewCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        if let result = try? await ProcessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "command -v brew"]
        ) {
            let detected = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0, !detected.isEmpty, FileManager.default.isExecutableFile(atPath: detected) {
                return detected
            }
        }

        return nil
    }
}

enum SetupError: LocalizedError {
    case commandFailed(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            return message
        case let .permissionDenied(message):
            return message
        }
    }
}

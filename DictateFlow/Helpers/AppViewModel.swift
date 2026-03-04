import Foundation
import SwiftUI
import AVFoundation

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var status: AppStatus = .ready
    @Published var statusMessage: String = AppStatus.ready.label
    @Published var isRecording = false
    @Published var isBusy = false

    @Published var selectedProfile: Profile = .email
    @Published var dictationMode: DictationMode
    @Published var selectedSpeechModel: SpeechModelOption

    @Published var history: [Transcription] = []
    @Published var alertItem: AlertItem?
    @Published var showSetupWizard = false

    private let settings: SettingsStore
    private let audioRecorder = AudioRecorder()
    private let whisperService = WhisperService()
    private let ollamaService = OllamaService.shared
    private let clipboardManager = ClipboardManager()
    private let commandProcessor = CommandProcessor()
    private let historyStore = HistoryStore()
    private let hotkeyManager = HotkeyManager()
    private let defaults = UserDefaults.standard

    private var didBootstrap = false

    private enum SetupKeys {
        static let didCompleteInitialSetup = "setup.didCompleteInitialSetup.v1"
    }

    init(settings: SettingsStore) {
        self.settings = settings
        dictationMode = settings.dictationMode
        selectedSpeechModel = settings.selectedSpeechModel
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        await runStartupEnvironmentChecks()
        showSetupWizard = shouldPresentSetupWizard()
        configureHotkey()
        await loadHistory()
    }

    func startRecording() async {
        guard !isRecording, !isBusy else { return }

        let hasPermission = await audioRecorder.requestPermissionIfNeeded()
        guard hasPermission else {
            setStatus(.failed)
            presentAlert(
                title: "Mikrofonzugriff fehlt",
                message: "Bitte aktiviere den Mikrofonzugriff für DictateFlow unter Systemeinstellungen > Datenschutz & Sicherheit > Mikrofon."
            )
            return
        }

        do {
            _ = try audioRecorder.startRecording()
            isRecording = true
            setStatus(.recording)
        } catch {
            setStatus(.failed)
            presentError(error, title: "Aufnahme konnte nicht gestartet werden")
        }
    }

    func stopRecording() async {
        guard isRecording else { return }

        guard let recordingURL = audioRecorder.stopRecording() else {
            isRecording = false
            setStatus(.failed)
            presentAlert(title: "Keine Aufnahme", message: "Es wurde keine aktive Aufnahme gefunden.")
            return
        }

        isRecording = false
        isBusy = true
        setStatus(.transcribing)

        await processRecording(at: recordingURL)
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func copyText(_ text: String) {
        clipboardManager.copy(text: text)
    }

    func updateTranscription(id: UUID, with newText: String) async {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }

        var item = history[index]
        item.processedText = newText

        do {
            try await historyStore.update(item)
            history[index] = item
        } catch {
            presentError(error, title: "Änderung konnte nicht gespeichert werden")
        }
    }

    func deleteTranscription(_ item: Transcription) async {
        do {
            try await historyStore.delete(id: item.id)
            history.removeAll { $0.id == item.id }
        } catch {
            presentError(error, title: "Eintrag konnte nicht gelöscht werden")
        }
    }

    func refreshHistory() async {
        await loadHistory()
    }

    func applyRecommendedWhisperModel() {
        let languageCode = Locale.current.language.languageCode?.identifier
        let recommended = WhisperModel.recommended(languageCode: languageCode, preferMaximumAccuracy: false)
        selectedSpeechModel = SpeechModelOption.from(whisperModel: recommended)
    }

    func applyMaximumAccuracyWhisperModel() {
        let maxAccuracy = WhisperModel.recommended(languageCode: nil, preferMaximumAccuracy: true)
        selectedSpeechModel = SpeechModelOption.from(whisperModel: maxAccuracy)
    }

    func openSetupWizard() {
        showSetupWizard = true
    }

    func finishSetupWizard(markedComplete: Bool) {
        if markedComplete {
            defaults.set(true, forKey: SetupKeys.didCompleteInitialSetup)
        }
        showSetupWizard = false

        Task {
            await runStartupEnvironmentChecks()
            showSetupWizard = shouldPresentSetupWizard()
        }
    }

    func shutdown() {
        ollamaService.stopServerIfManagedByApp()
    }

    private func processRecording(at recordingURL: URL) async {
        defer {
            isBusy = false
            try? FileManager.default.removeItem(at: recordingURL)
        }

        do {
            let rawText = try await whisperService.transcribe(
                audioURL: recordingURL,
                model: selectedSpeechModel.runtimeWhisperModel,
                binaryPath: settings.whisperBinaryPath,
                modelDirectory: settings.whisperModelDirectory
            )

            var outputText = rawText

            if dictationMode == .aiPrompt {
                setStatus(.postProcessing)

                // Sprachbefehle wie "neuer Absatz" vor dem LLM auswerten.
                let textForPrompt = commandProcessor.apply(to: rawText)
                let renderedPrompt = settings.renderPrompt(
                    text: textForPrompt,
                    profileHint: selectedProfile.llmHint
                )

                do {
                    outputText = try await ollamaService.refine(
                        prompt: renderedPrompt,
                        model: settings.ollamaModel,
                        binaryPath: settings.ollamaBinaryPath
                    )
                } catch {
                    outputText = textForPrompt
                    let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    presentAlert(
                        title: "KI-Nachbearbeitung übersprungen",
                        message: "\(detail)\n\nDie Transkription wurde ohne KI-Nachbearbeitung fortgesetzt."
                    )
                }
            }

            let transcription = Transcription(
                profile: selectedProfile,
                rawText: rawText,
                processedText: outputText
            )

            try await historyStore.insert(transcription)
            history.insert(transcription, at: 0)

            let hasAccessibilityPermission = await clipboardManager.requestAccessibilityPermissionAndWait(
                prompt: true,
                timeout: 6,
                pollInterval: 0.4
            )

            if hasAccessibilityPermission {
                do {
                    try clipboardManager.copyAndPaste(text: outputText, promptForAccessibility: false)
                } catch {
                    clipboardManager.copy(text: outputText)
                    let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    presentAlert(
                        title: "Einfügen eingeschränkt",
                        message: "\(detail)\n\nDas Transkript wurde in die Zwischenablage kopiert."
                    )
                }
            } else {
                clipboardManager.copy(text: outputText)
                presentAlert(
                    title: "Einfügen eingeschränkt",
                    message: "Das Transkript wurde in die Zwischenablage kopiert. Für automatisches Einfügen bitte Bedienungshilfen erlauben.\n\n\(clipboardManager.accessibilityTroubleshootingHint())"
                )
            }

            setStatus(.ready)
        } catch {
            setStatus(.failed)
            presentError(error, title: "Transkription fehlgeschlagen")
        }
    }

    private func loadHistory() async {
        do {
            history = try await historyStore.fetchAll()
        } catch {
            presentError(error, title: "Verlauf konnte nicht geladen werden")
        }
    }

    private func configureHotkey() {
        hotkeyManager.onHotKeyPressed = { [weak self] in
            guard let self else { return }
            Task {
                await self.handleHotkeyTrigger()
            }
        }

        do {
            try hotkeyManager.registerDefaultShortcut()
        } catch {
            presentError(error, title: "Globaler Hotkey konnte nicht registriert werden")
        }
    }

    private func handleHotkeyTrigger() async {
        if isBusy {
            return
        }

        await toggleRecording()
    }

    private func runStartupEnvironmentChecks() async {
        let resolvedWhisperPath = WhisperService.resolveWhisperBinaryPath(preferredPath: settings.whisperBinaryPath)
        let resolvedOllamaPath = OllamaService.resolveOllamaBinaryPath(preferredPath: settings.ollamaBinaryPath)

        if let resolvedWhisperPath {
            settings.whisperBinaryPath = resolvedWhisperPath
        }
        if let resolvedOllamaPath {
            settings.ollamaBinaryPath = resolvedOllamaPath
        }

        if let resolvedOllamaPath {
            do {
                try await ollamaService.ensureServerRunning(binaryPath: resolvedOllamaPath)
            } catch {
                // Im Initial-Setup übernimmt der Assistent die Kommunikation.
                if defaults.bool(forKey: SetupKeys.didCompleteInitialSetup) {
                    presentAlert(
                        title: "Ollama-Server konnte nicht gestartet werden",
                        message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                }
            }
        }
    }

    private func shouldPresentSetupWizard() -> Bool {
        let didCompleteSetup = defaults.bool(forKey: SetupKeys.didCompleteInitialSetup)

        let hasWhisper = WhisperService.resolveWhisperBinaryPath(preferredPath: settings.whisperBinaryPath) != nil
        let hasOllama = OllamaService.resolveOllamaBinaryPath(preferredPath: settings.ollamaBinaryPath) != nil
        let hasMicrophonePermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let hasAccessibilityPermission = clipboardManager.hasAccessibilityPermission()

        let allReady = hasWhisper && hasOllama && hasMicrophonePermission && hasAccessibilityPermission

        if !didCompleteSetup {
            return true
        }

        return !allReady
    }

    private func setStatus(_ newStatus: AppStatus, message: String? = nil) {
        status = newStatus
        statusMessage = message ?? newStatus.label
    }

    private func presentError(_ error: Error, title: String) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentAlert(title: title, message: message)
    }

    private func presentAlert(title: String, message: String) {
        alertItem = AlertItem(title: title, message: message)
    }
}

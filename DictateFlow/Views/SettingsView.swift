import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var binaryDetectFeedback = ""
    @State private var modelDetectFeedback = ""
    @State private var modelDownloadFeedback = ""
    @State private var ollamaDetectFeedback = ""
    @State private var isDownloadingModel = false

    private let whisperService = WhisperService()

    var body: some View {
        Form {
            Section("whisper.cpp") {
                HStack {
                    TextField("Pfad zu whisper-cli", text: $settings.whisperBinaryPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Auswählen…") {
                        chooseWhisperBinary()
                    }
                }

                HStack(spacing: 10) {
                    Button("Whisper automatisch finden") {
                        if settings.autoDetectWhisperBinaryPath() {
                            binaryDetectFeedback = "CLI gefunden: \(settings.whisperBinaryPath)"
                        } else {
                            binaryDetectFeedback = "Kein whisper-cli gefunden. Installiere whisper.cpp oder wähle die Datei manuell aus."
                        }
                    }
                    .buttonStyle(.bordered)

                    if !binaryDetectFeedback.isEmpty {
                        Text(binaryDetectFeedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    TextField("Modellordner (ggml-*.bin)", text: $settings.whisperModelDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Auswählen…") {
                        chooseModelDirectory()
                    }
                }

                HStack(spacing: 10) {
                    Button("Modellordner automatisch finden") {
                        if settings.autoDetectWhisperModelDirectory() {
                            modelDetectFeedback = "Modellordner gefunden: \(settings.whisperModelDirectory)"
                        } else {
                            modelDetectFeedback = "Kein Modellordner mit ggml-*.bin gefunden. Lade z. B. ggml-small.bin herunter."
                        }
                    }
                    .buttonStyle(.bordered)

                    if !modelDetectFeedback.isEmpty {
                        Text(modelDetectFeedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button("Small herunterladen (DE/EU)") {
                            downloadModel(.small)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDownloadingModel)

                        Button("Medium herunterladen (JA/ZH)") {
                            downloadModel(.medium)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDownloadingModel)

                        Button("Large v3 herunterladen") {
                            downloadModel(.largeV3)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDownloadingModel)
                    }

                    if isDownloadingModel {
                        ProgressView("Modell wird geladen…")
                    }

                    if !modelDownloadFeedback.isEmpty {
                        Text(modelDownloadFeedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Lokale KI (Ollama)") {
                HStack {
                    TextField("Pfad zu ollama", text: $settings.ollamaBinaryPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Auswählen…") {
                        chooseOllamaBinary()
                    }
                }

                HStack(spacing: 10) {
                    Button("Ollama automatisch finden") {
                        if settings.autoDetectOllamaBinaryPath() {
                            ollamaDetectFeedback = "Ollama CLI gefunden: \(settings.ollamaBinaryPath)"
                        } else {
                            ollamaDetectFeedback = "Kein ollama CLI gefunden. Installiere Ollama oder wähle die Datei manuell aus."
                        }
                    }
                    .buttonStyle(.bordered)

                    if !ollamaDetectFeedback.isEmpty {
                        Text(ollamaDetectFeedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Modellname", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)

                Toggle("KI standardmäßig aktivieren", isOn: $settings.enablePostProcessingByDefault)
            }

            Section("Standardprompt") {
                TextEditor(text: $settings.defaultPrompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 170)

                HStack {
                    Spacer()
                    Button("Prompt zurücksetzen") {
                        settings.resetPromptToDefault()
                    }
                }
            }

            Section("Setup") {
                Button("Einrichtungsassistent öffnen") {
                    appViewModel.openSetupWizard()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    private func chooseWhisperBinary() {
        let panel = NSOpenPanel()
        panel.title = "whisper.cpp CLI auswählen"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settings.whisperBinaryPath = url.path
        }
    }

    private func chooseModelDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Whisper Modellordner auswählen"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settings.whisperModelDirectory = url.path
        }
    }

    private func chooseOllamaBinary() {
        let panel = NSOpenPanel()
        panel.title = "Ollama CLI auswählen"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settings.ollamaBinaryPath = url.path
        }
    }

    private func downloadModel(_ model: WhisperModel) {
        Task {
            isDownloadingModel = true
            defer { isDownloadingModel = false }

            let originalDirectory = settings.whisperModelDirectory
            let targetDirectory = settings.ensureWritableModelDirectory()

            do {
                let outputURL = try await whisperService.downloadModel(model, to: targetDirectory)
                settings.whisperModelDirectory = outputURL.deletingLastPathComponent().path
                if originalDirectory != settings.whisperModelDirectory {
                    modelDownloadFeedback = "Modell geladen: \(outputURL.lastPathComponent). Downloadpfad wurde auf einen beschreibbaren User-Ordner umgestellt."
                } else {
                    modelDownloadFeedback = "Modell geladen: \(outputURL.lastPathComponent)"
                }
            } catch {
                modelDownloadFeedback = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

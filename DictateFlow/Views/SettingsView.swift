import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var binaryDetectFeedback = ""
    @State private var modelDetectFeedback = ""
    @State private var ollamaDetectFeedback = ""
    @State private var showModelSelectionWindow = false

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
            }

            Section("Diktiermodus") {
                Picker("Standardmodus", selection: $settings.dictationMode) {
                    ForEach(DictationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("LMM-Auswahl") {
                HStack {
                    Text("Aktives Modell")
                    Spacer()
                    Text(settings.selectedSpeechModel.displayName)
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Größe: \(settings.selectedSpeechModel.sizeLabel) | " +
                    "Speed: \(settings.selectedSpeechModel.speedLabel) | " +
                    "Genauigkeit: \(settings.selectedSpeechModel.accuracyLabel)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("LMM-Auswahlfenster öffnen") {
                    showModelSelectionWindow = true
                }
                .buttonStyle(.borderedProminent)

                Text("Nicht installierte Modelle können direkt im Auswahlfenster heruntergeladen werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("KI-Prompt") {
                Picker("Prompt-Stil", selection: $settings.promptStyle) {
                    ForEach(PromptStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                if settings.promptStyle == .custom {
                    TextField("Benutzerdefinierter Stil", text: $settings.customStyleInstruction)
                        .textFieldStyle(.roundedBorder)
                }

                TextEditor(text: $settings.promptTemplate)
                    .font(.body.monospaced())
                    .frame(minHeight: 210)

                Text("Platzhalter: {{style_instruction}}, {{profile_hint}}, {{text}}")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
        .onChange(of: settings.dictationMode) {
            appViewModel.dictationMode = settings.dictationMode
        }
        .onChange(of: settings.selectedSpeechModel) {
            appViewModel.selectedSpeechModel = settings.selectedSpeechModel
        }
        .sheet(isPresented: $showModelSelectionWindow) {
            ModelSelectionView(selectedModel: $settings.selectedSpeechModel) {
                showModelSelectionWindow = false
            }
        }
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
}

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var binaryDetectFeedback = ""
    @State private var modelDetectFeedback = ""
    @State private var ollamaDetectFeedback = ""
    @State private var launchAtLoginFeedback = ""
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

            Section("Einfügen & Overlay") {
                Toggle("Text automatisch einfügen", isOn: $settings.autoPasteEnabled)

                Text("Wenn deaktiviert, wird der Text nur in die Zwischenablage kopiert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Overlay anzeigen (immer im Vordergrund)", isOn: $settings.showFloatingOverlay)

                HStack {
                    Button("Position zurücksetzen") {
                        appViewModel.resetFloatingOverlayPosition()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if let origin = settings.overlayOriginPoint {
                        Text("Aktuell: x \(Int(origin.x)), y \(Int(origin.y))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Sprache") {
                Picker("Transkriptionssprache", selection: $settings.primaryTranscriptionLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                DisclosureGroup("Zusätzliche Sprachen (Fallback)") {
                    ForEach(
                        TranscriptionLanguage.fallbackChoices.filter { $0 != settings.primaryTranscriptionLanguage },
                        id: \.self
                    ) { language in
                        Toggle(language.displayName, isOn: fallbackBinding(for: language))
                    }
                }

                Text("Wenn die primäre Sprache fehlschlägt, testet DictateFlow die Fallback-Sprachen in Reihenfolge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                Picker("Taste", selection: $settings.hotkeyKey) {
                    ForEach(HotkeyKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }

                HStack(spacing: 14) {
                    Toggle("⌘", isOn: $settings.hotkeyUseCommand)
                    Toggle("⇧", isOn: $settings.hotkeyUseShift)
                    Toggle("⌥", isOn: $settings.hotkeyUseOption)
                    Toggle("⌃", isOn: $settings.hotkeyUseControl)
                }

                Text("Aktuell: \(settings.hotkeyDisplayString())")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Push-to-Talk", isOn: $settings.pushToTalkEnabled)

                if settings.pushToTalkEnabled {
                    Text("Halte den Shortcut gedrückt, während du sprichst.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("System") {
                Toggle("Bei Anmeldung starten", isOn: $settings.launchAtLoginEnabled)

                if !launchAtLoginFeedback.isEmpty {
                    Text(launchAtLoginFeedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .onChange(of: settings.showFloatingOverlay) {
            appViewModel.applyFloatingOverlayVisibilitySetting()
        }
        .onChange(of: settings.hotkeyKey) {
            appViewModel.reconfigureHotkeyFromSettings()
        }
        .onChange(of: settings.hotkeyUseCommand) {
            handleHotkeyModifierChanged()
        }
        .onChange(of: settings.hotkeyUseShift) {
            handleHotkeyModifierChanged()
        }
        .onChange(of: settings.hotkeyUseOption) {
            handleHotkeyModifierChanged()
        }
        .onChange(of: settings.hotkeyUseControl) {
            handleHotkeyModifierChanged()
        }
        .onChange(of: settings.pushToTalkEnabled) {
            appViewModel.reconfigureHotkeyFromSettings()
        }
        .onChange(of: settings.launchAtLoginEnabled) {
            Task {
                await appViewModel.applyLaunchAtLoginSetting()
                launchAtLoginFeedback = settings.launchAtLoginEnabled ?
                    "Bei Anmeldung starten ist aktiv." :
                    "Bei Anmeldung starten ist deaktiviert."
            }
        }
        .sheet(isPresented: $showModelSelectionWindow) {
            ModelSelectionView(selectedModel: $settings.selectedSpeechModel) {
                showModelSelectionWindow = false
            }
        }
    }

    private func fallbackBinding(for language: TranscriptionLanguage) -> Binding<Bool> {
        Binding(
            get: {
                settings.fallbackTranscriptionLanguages.contains(language)
            },
            set: { isEnabled in
                if isEnabled {
                    settings.fallbackTranscriptionLanguages.insert(language)
                } else {
                    settings.fallbackTranscriptionLanguages.remove(language)
                }
            }
        )
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

    private func handleHotkeyModifierChanged() {
        settings.ensureAtLeastOneHotkeyModifier()
        appViewModel.reconfigureHotkeyFromSettings()
    }
}

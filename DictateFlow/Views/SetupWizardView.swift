import SwiftUI

struct SetupWizardView: View {
    @StateObject private var viewModel: SetupWizardViewModel

    private let onFinish: (_ markedComplete: Bool) -> Void

    @State private var showHomebrewInstallConfirmation = false

    init(settings: SettingsStore, onFinish: @escaping (_ markedComplete: Bool) -> Void) {
        _viewModel = StateObject(wrappedValue: SetupWizardViewModel(settings: settings))
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            Group {
                switch viewModel.currentStep {
                case .homebrew:
                    homebrewStep
                case .tools:
                    toolsStep
                case .permissions:
                    permissionsStep
                case .complete:
                    completionStep
                }
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 640, height: 470)
        .task {
            await viewModel.refreshAll()
        }
        .alert("Homebrew installieren?", isPresented: $showHomebrewInstallConfirmation) {
            Button("Installieren") {
                Task {
                    await viewModel.installHomebrew()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Homebrew wird auf diesem Mac installiert. Danach können wir ollama und whisper-cpp automatisch installieren.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Einrichtungsassistent")
                .font(.title3.weight(.semibold))

            Text(viewModel.currentStep.subtitle)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(SetupStep.allCases) { step in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(step.rawValue <= viewModel.currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 10, height: 10)
                        Text(step.title)
                            .font(.caption2)
                            .foregroundStyle(step.rawValue == viewModel.currentStep.rawValue ? .primary : .secondary)
                    }
                    if step != SetupStep.allCases.last {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private var homebrewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(title: "Homebrew", ok: viewModel.isBrewInstalled, okText: "Installiert", missingText: "Nicht gefunden")

            if !viewModel.brewPath.isEmpty {
                Text("Pfad: \(viewModel.brewPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Status prüfen") {
                    Task { await viewModel.refreshAll() }
                }
                .buttonStyle(.bordered)

                Button("Homebrew installieren") {
                    showHomebrewInstallConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking || viewModel.isBrewInstalled)

                Button("Im Terminal installieren") {
                    viewModel.installHomebrewInTerminal()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isWorking || viewModel.isBrewInstalled)
            }

            Text("Hinweis: Bei der Installation kann macOS nach deinem Passwort fragen.")
                .font(.caption)
                .foregroundStyle(.secondary)

            logsView
        }
    }

    private var toolsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(title: "whisper.cpp CLI", ok: viewModel.isWhisperInstalled, okText: "Installiert", missingText: "Fehlt")
            statusRow(title: "Whisper-Modell", ok: viewModel.isWhisperModelAvailable, okText: "Vorhanden", missingText: "Fehlt")
            statusRow(title: "ollama CLI", ok: viewModel.isOllamaInstalled, okText: "Installiert", missingText: "Fehlt")
            statusRow(title: "ollama server", ok: viewModel.isOllamaServerRunning, okText: "Läuft", missingText: "Nicht aktiv")

            HStack(spacing: 10) {
                Button("whisper-cpp installieren") {
                    Task { await viewModel.installWhisperCpp() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isWorking || !viewModel.isBrewInstalled)

                Button("Small-Modell laden") {
                    Task { await viewModel.downloadRecommendedWhisperModel() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isWorking)
            }

            HStack(spacing: 10) {
                Button("ollama installieren") {
                    Task { await viewModel.installOllama() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isWorking || !viewModel.isBrewInstalled)

                Button("ollama server starten") {
                    Task { await viewModel.startOllamaServer() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking || !viewModel.isOllamaInstalled)
            }

            logsView
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(title: "Mikrofon", ok: viewModel.isMicrophoneGranted, okText: "Freigegeben", missingText: "Nicht freigegeben")
            statusRow(title: "Bedienungshilfen", ok: viewModel.isAccessibilityGranted, okText: "Freigegeben", missingText: "Nicht freigegeben")

            HStack(spacing: 10) {
                Button("Mikrofon erlauben") {
                    Task { await viewModel.requestMicrophonePermission() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isWorking)

                Button("Bedienungshilfe erlauben") {
                    Task { await viewModel.requestAccessibilityPermission() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isWorking)
            }

            HStack(spacing: 10) {
                Button("Mikrofon-Einstellungen öffnen") {
                    viewModel.openSystemSettings(anchor: "Privacy_Microphone")
                }
                .buttonStyle(.link)

                Button("Bedienungshilfe-Einstellungen öffnen") {
                    viewModel.openSystemSettings(anchor: "Privacy_Accessibility")
                }
                .buttonStyle(.link)
            }

            logsView
        }
    }

    private var completionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isSetupComplete {
                Label("Setup abgeschlossen", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text("Alle Komponenten sind eingerichtet. Du kannst jetzt direkt aufnehmen und transkribieren.")
            } else {
                Label("Setup noch unvollständig", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
                Text("Gehe mit 'Zurück' zu den vorherigen Schritten und vervollständige die fehlenden Punkte.")
            }

            logsView
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isWorking {
                ProgressView(viewModel.statusMessage)
            }

            if !viewModel.lastErrorMessage.isEmpty {
                Text(viewModel.lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Abbrechen") {
                    onFinish(false)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Zurück") {
                    viewModel.previousStep()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canGoBack || viewModel.isWorking)

                if viewModel.currentStep == .complete {
                    Button("Fertig") {
                        onFinish(viewModel.isSetupComplete)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Weiter") {
                        viewModel.nextStep()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canGoNext || !viewModel.isCurrentStepSatisfied || viewModel.isWorking)
                }
            }
        }
    }

    private var logsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if viewModel.logLines.isEmpty {
                    Text("Noch keine Aktionen ausgeführt.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 120)
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusRow(title: String, ok: Bool, okText: String, missingText: String) -> some View {
        HStack {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
            Spacer()
            Text(ok ? okText : missingText)
                .font(.caption)
                .foregroundStyle(ok ? .green : .secondary)
        }
    }
}

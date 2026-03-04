import SwiftUI

struct MainView: View {
    private enum Tab: Hashable {
        case recorder
        case history
        case settings
    }

    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: SettingsStore

    @State private var selectedTab: Tab = .recorder
    @State private var availableRuntimeModels: Set<WhisperModel> = []

    private let whisperService = WhisperService()

    var body: some View {
        TabView(selection: $selectedTab) {
            recorderView
                .tabItem {
                    Label("Aufnahme", systemImage: "mic")
                }
                .tag(Tab.recorder)

            HistoryView()
                .tabItem {
                    Label("Verlauf", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tab.history)

            SettingsView()
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .overlay(alignment: .top) {
            OverlayView(status: viewModel.status, message: viewModel.statusMessage)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
        .alert(item: $viewModel.alertItem) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            await viewModel.bootstrapIfNeeded()
            refreshModelAvailability()
        }
        .sheet(isPresented: $viewModel.showSetupWizard) {
            SetupWizardView(settings: settings) { markedComplete in
                viewModel.finishSetupWizard(markedComplete: markedComplete)
            }
        }
        .onChange(of: viewModel.selectedSpeechModel) {
            settings.selectedSpeechModel = viewModel.selectedSpeechModel
        }
        .onChange(of: viewModel.dictationMode) {
            settings.dictationMode = viewModel.dictationMode
        }
        .onChange(of: settings.whisperModelDirectory) {
            refreshModelAvailability()
        }
        .onChange(of: settings.whisperBinaryPath) {
            refreshModelAvailability()
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private var recorderView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Status") {
                HStack(spacing: 12) {
                    Label(viewModel.status.label, systemImage: viewModel.status.iconName)
                        .font(.headline)
                        .foregroundStyle(viewModel.status.bannerColor)

                    Spacer()

                    Text("Hotkey: ⌘⇧D")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("Aufnahme") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            Task { await viewModel.startRecording() }
                        } label: {
                            Label("Start", systemImage: "record.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRecording || viewModel.isBusy)

                        Button {
                            Task { await viewModel.stopRecording() }
                        } label: {
                            Label("Stopp", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRecording)
                    }

                    HStack(spacing: 14) {
                        Picker("LMM-Modell", selection: $viewModel.selectedSpeechModel) {
                            ForEach(SpeechModelOption.allCases) { model in
                                Text(isSpeechModelAvailable(model) ? model.displayName : "\(model.displayName) (nicht installiert)")
                                    .tag(model)
                                    .disabled(!isSpeechModelAvailable(model))
                            }
                        }
                        .frame(width: 280)

                        Picker("Modus", selection: $viewModel.dictationMode) {
                            ForEach(DictationMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .frame(width: 280)
                    }

                    Picker("Prompt-Stil", selection: $settings.promptStyle) {
                        ForEach(PromptStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .frame(width: 360)

                    if viewModel.dictationMode == .plain {
                        Text("Prompt-Stil wird bei 'Reines Diktat' nicht angewendet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(viewModel.dictationMode.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Profil", selection: $viewModel.selectedProfile) {
                        ForEach(Profile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .frame(width: 360)
                }
                .padding(8)
            }

            GroupBox("Letzte Transkriptionen") {
                List {
                    if viewModel.history.isEmpty {
                        Text("Noch keine Transkriptionen vorhanden.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.history.prefix(10))) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(item.profile.displayName, systemImage: item.profile.systemImage)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Text(item.displayText)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button("Kopieren") {
                                    viewModel.copyText(item.displayText)
                                }
                                Button("Löschen", role: .destructive) {
                                    Task {
                                        await viewModel.deleteTranscription(item)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 300)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func isSpeechModelAvailable(_ option: SpeechModelOption) -> Bool {
        availableRuntimeModels.contains(option.runtimeWhisperModel)
    }

    private func refreshModelAvailability() {
        availableRuntimeModels = whisperService.availableModels(
            modelDirectory: settings.whisperModelDirectory,
            binaryPath: settings.whisperBinaryPath
        )

        guard !availableRuntimeModels.isEmpty else { return }

        if !isSpeechModelAvailable(viewModel.selectedSpeechModel),
           let firstAvailable = SpeechModelOption.allCases.first(where: { isSpeechModelAvailable($0) }) {
            viewModel.selectedSpeechModel = firstAvailable
        }
    }
}

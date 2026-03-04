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
            if shouldShowTopStatusBanner {
                OverlayView(status: viewModel.status, message: viewModel.statusMessage)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .dictateFlowOpenRecorderTab)) { _ in
            selectedTab = .recorder
        }
        .onReceive(NotificationCenter.default.publisher(for: .dictateFlowOpenSettingsTab)) { _ in
            selectedTab = .settings
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private var shouldShowTopStatusBanner: Bool {
        viewModel.isRecording || viewModel.isBusy || viewModel.status == .failed
    }

    private var recorderView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aufnahme")
                            .font(.title2.weight(.semibold))
                        Text("Lokales Diktat mit optionaler KI-Nachbearbeitung.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                card(title: "Status") {
                    HStack(spacing: 12) {
                        Label(viewModel.status.label, systemImage: viewModel.status.iconName)
                            .font(.headline)
                            .foregroundStyle(viewModel.status.bannerColor)

                        Spacer()

                        Text("Hotkey: \(settings.hotkeyDisplayString())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                card(title: "Diktieren") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Button {
                                Task { await viewModel.startRecording() }
                            } label: {
                                Label("Start", systemImage: "record.circle")
                                    .frame(minWidth: 92)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isRecording || viewModel.isBusy)

                            Button {
                                Task { await viewModel.stopRecording() }
                            } label: {
                                Label("Stopp", systemImage: "stop.circle")
                                    .frame(minWidth: 92)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.isRecording)
                        }

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                            GridRow {
                                Text("Profil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Profil", selection: $viewModel.selectedProfile) {
                                    ForEach(Profile.allCases) { profile in
                                        Text(profile.displayName).tag(profile)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GridRow {
                                Text("Modus")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Modus", selection: $viewModel.dictationMode) {
                                    ForEach(DictationMode.allCases) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GridRow {
                                Text("LMM-Modell")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("LMM-Modell", selection: $viewModel.selectedSpeechModel) {
                                    ForEach(SpeechModelOption.allCases) { model in
                                        Text(
                                            isSpeechModelAvailable(model)
                                            ? model.displayName
                                            : "\(model.displayName) (nicht installiert)"
                                        )
                                        .tag(model)
                                        .disabled(!isSpeechModelAvailable(model))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if viewModel.dictationMode == .aiPrompt {
                                GridRow {
                                    Text("Prompt-Stil")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Prompt-Stil", selection: $settings.promptStyle) {
                                        ForEach(PromptStyle.allCases) { style in
                                            Text(style.displayName).tag(style)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        Text(viewModel.dictationMode.descriptionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                card(title: "Letzte Transkriptionen") {
                    if viewModel.history.isEmpty {
                        ContentUnavailableView(
                            "Noch keine Transkriptionen",
                            systemImage: "text.bubble",
                            description: Text("Starte eine Aufnahme, um den Verlauf zu füllen.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(viewModel.history.prefix(8))) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
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
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Button {
                                        viewModel.copyText(item.displayText)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Kopieren")
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.secondary.opacity(0.08))
                                )
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

                        HStack {
                            Spacer()
                            Button("Vollen Verlauf öffnen") {
                                selectedTab = .history
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}

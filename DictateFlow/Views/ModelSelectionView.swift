import SwiftUI

struct ModelSelectionView: View {
    @EnvironmentObject private var settings: SettingsStore

    @Binding var selectedModel: SpeechModelOption

    let onClose: () -> Void

    @State private var availableRuntimeModels: Set<WhisperModel> = []
    @State private var currentlyDownloading: WhisperModel?
    @State private var statusMessage = ""

    private let whisperService = WhisperService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LMM-Auswahl")
                .font(.title3.weight(.semibold))

            Text("Wähle ein Modell basierend auf Größe, Geschwindigkeit und Genauigkeit. Nur installierte Modelle sind auswählbar.")
                .foregroundStyle(.secondary)

            headerRow

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(SpeechModelOption.allCases) { model in
                        row(for: model)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if currentlyDownloading != nil {
                ProgressView("Modell wird heruntergeladen…")
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Schließen") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 760, height: 460)
        .task {
            refreshAvailability()
        }
        .onChange(of: settings.whisperModelDirectory) {
            refreshAvailability()
        }
        .onChange(of: settings.whisperBinaryPath) {
            refreshAvailability()
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Modell")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Größe")
                .font(.caption.weight(.semibold))
                .frame(width: 110, alignment: .leading)
            Text("Speed")
                .font(.caption.weight(.semibold))
                .frame(width: 120, alignment: .leading)
            Text("Genauigkeit")
                .font(.caption.weight(.semibold))
                .frame(width: 120, alignment: .leading)
            Text("Status / Aktion")
                .font(.caption.weight(.semibold))
                .frame(width: 190, alignment: .trailing)
        }
        .foregroundStyle(.secondary)
    }

    private func row(for model: SpeechModelOption) -> some View {
        let isAvailable = isOptionAvailable(model)
        let isDownloadingThisModel = currentlyDownloading == model.runtimeWhisperModel

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(.body.weight(.medium))
                Text(model.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(model.sizeLabel)
                .font(.subheadline)
                .frame(width: 110, alignment: .leading)

            Text(model.speedLabel)
                .font(.subheadline)
                .frame(width: 120, alignment: .leading)

            Text(model.accuracyLabel)
                .font(.subheadline)
                .frame(width: 120, alignment: .leading)

            if selectedModel == model && isAvailable {
                Label("Aktiv", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 190, alignment: .trailing)
            } else if isAvailable {
                Button("Wählen") {
                    selectedModel = model
                    statusMessage = ""
                }
                .buttonStyle(.bordered)
                .frame(width: 190, alignment: .trailing)
            } else if isDownloadingThisModel {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Download läuft")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 190, alignment: .trailing)
            } else {
                HStack(spacing: 8) {
                    Text("Nicht installiert")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Download") {
                        Task {
                            await downloadModel(for: model)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentlyDownloading != nil)
                }
                .frame(width: 190, alignment: .trailing)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedModel == model ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedModel == model ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    private func isOptionAvailable(_ option: SpeechModelOption) -> Bool {
        availableRuntimeModels.contains(option.runtimeWhisperModel)
    }

    private func refreshAvailability() {
        availableRuntimeModels = whisperService.availableModels(
            modelDirectory: settings.whisperModelDirectory,
            binaryPath: settings.whisperBinaryPath
        )

        guard !isOptionAvailable(selectedModel) else {
            return
        }

        if let firstAvailable = SpeechModelOption.allCases.first(where: { isOptionAvailable($0) }) {
            selectedModel = firstAvailable
            statusMessage = "Aktives Modell war nicht installiert. Auf \(firstAvailable.displayName) umgestellt."
        } else {
            statusMessage = "Kein lokales Modell gefunden. Bitte zuerst ein Modell herunterladen."
        }
    }

    @MainActor
    private func downloadModel(for option: SpeechModelOption) async {
        let runtimeModel = option.runtimeWhisperModel
        currentlyDownloading = runtimeModel
        statusMessage = ""

        let previousDirectory = settings.whisperModelDirectory
        let targetDirectory = settings.ensureWritableModelDirectory()

        defer {
            currentlyDownloading = nil
            refreshAvailability()
        }

        do {
            let outputURL = try await whisperService.downloadModel(runtimeModel, to: targetDirectory)
            settings.whisperModelDirectory = outputURL.deletingLastPathComponent().path
            selectedModel = option

            if previousDirectory != settings.whisperModelDirectory {
                statusMessage = "Modell geladen: \(outputURL.lastPathComponent). Downloadpfad wurde auf einen beschreibbaren User-Ordner umgestellt."
            } else {
                statusMessage = "Modell geladen: \(outputURL.lastPathComponent)"
            }
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

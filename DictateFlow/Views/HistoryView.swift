import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    @State private var selectedID: UUID?
    @State private var draftText = ""

    private var selectedTranscription: Transcription? {
        guard let selectedID else { return nil }
        return viewModel.history.first(where: { $0.id == selectedID })
    }

    var body: some View {
        HSplitView {
            List(viewModel.history, selection: $selectedID) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(item.profile.displayName, systemImage: item.profile.systemImage)
                            .font(.headline)
                        Spacer()
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.displayText)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(item.id)
            }
            .frame(minWidth: 340)

            detailPanel
                .frame(minWidth: 500)
        }
        .onAppear {
            ensureSelection()
        }
        .onChange(of: selectedID) {
            syncDraftWithSelection()
        }
        .onChange(of: viewModel.history) {
            ensureSelection()
        }
        .padding(16)
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let item = selectedTranscription {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(item.profile.displayName, systemImage: item.profile.systemImage)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(item.createdAt.formatted(date: .complete, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $draftText)
                    .font(.body)
                    .frame(minHeight: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    Button("Kopieren") {
                        viewModel.copyText(draftText)
                    }

                    Button("Speichern") {
                        Task {
                            await viewModel.updateTranscription(id: item.id, with: draftText)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Löschen", role: .destructive) {
                        Task {
                            await viewModel.deleteTranscription(item)
                            selectedID = viewModel.history.first?.id
                            syncDraftWithSelection()
                        }
                    }

                    Spacer()
                }
            }
        } else {
            ContentUnavailableView("Kein Verlaufseintrag ausgewählt", systemImage: "clock.arrow.circlepath")
        }
    }

    private func ensureSelection() {
        if selectedID == nil {
            selectedID = viewModel.history.first?.id
            syncDraftWithSelection()
            return
        }

        guard let selectedID else { return }
        if viewModel.history.contains(where: { $0.id == selectedID }) == false {
            self.selectedID = viewModel.history.first?.id
            syncDraftWithSelection()
        }
    }

    private func syncDraftWithSelection() {
        draftText = selectedTranscription?.displayText ?? ""
    }
}

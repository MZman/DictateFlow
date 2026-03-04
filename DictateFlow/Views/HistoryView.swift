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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Verlauf")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(viewModel.history.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                        )
                }

                if viewModel.history.isEmpty {
                    ContentUnavailableView(
                        "Keine Transkripte vorhanden",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Sobald du aufnimmst, erscheint der Verlauf hier.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.history, selection: $selectedID) { item in
                        VStack(alignment: .leading, spacing: 5) {
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
                        .padding(.vertical, 4)
                        .tag(item.id)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            )
            .frame(minWidth: 340)

            detailPanel
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )
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
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
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

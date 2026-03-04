import SwiftUI
import AppKit

struct MenuBarControlView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    @State private var availableInputDevices: [AudioInputDevice] = []
    private let panelWidth: CGFloat = 250

    var body: some View {
        VStack(spacing: 0) {
            statusSection
            sectionDivider
            transcriptSection
            sectionDivider
            microphoneSection
            sectionDivider
            actionSection
        }
        .padding(6)
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .task {
            await viewModel.bootstrapIfNeeded()
            refreshInputDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshInputDevices()
        }
    }

    private var statusSection: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(viewModel.status.bannerColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.status.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.status.bannerColor)
                Text(viewModel.statusMessage)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Letzte Transkription")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(lastTranscriptionPreview)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(4)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
    }

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mikrofon")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Mikrofon", selection: $settings.preferredInputDeviceUID) {
                Text("Systemstandard").tag("")
                ForEach(availableInputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .labelsHidden()
            .font(.system(size: 11, weight: .regular))
            .frame(maxWidth: .infinity, alignment: .leading)

            if !settings.preferredInputDeviceUID.isEmpty,
               availableInputDevices.contains(where: { $0.id == settings.preferredInputDeviceUID }) == false {
                Text("Ausgewähltes Gerät ist nicht verfügbar, daher wird Systemstandard genutzt.")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
    }

    private var actionSection: some View {
        VStack(spacing: 0) {
            menuRowButton(
                title: viewModel.isRecording ? "Aufnahme stoppen" : "Aufnahme starten",
                systemImage: viewModel.isRecording ? "stop.fill" : "mic",
                shortcut: settings.hotkeyDisplayString()
            ) {
                Task {
                    if viewModel.isRecording {
                        await viewModel.stopRecording()
                    } else {
                        await viewModel.startRecording()
                    }
                }
            }

            sectionDivider

            menuRowButton(title: "Einstellungen", systemImage: "gearshape", shortcut: "⌘,") {
                openMainWindow()
                NotificationCenter.default.post(name: .dictateFlowOpenSettingsTab, object: nil)
            }

            sectionDivider

            menuRowButton(title: "DictateFlow beenden", systemImage: "power", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var statusIconName: String {
        switch viewModel.status {
        case .ready:
            return "checkmark.circle"
        case .recording:
            return "record.circle"
        case .transcribing:
            return "waveform"
        case .postProcessing:
            return "sparkles"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var lastTranscriptionPreview: String {
        guard let latest = viewModel.history.first?.displayText else {
            return "Noch keine Transkription."
        }

        let cleaned = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return "Noch keine Transkription."
        }

        let normalizedWhitespace = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalizedWhitespace
    }

    private func refreshInputDevices() {
        availableInputDevices = AudioInputDeviceManager.availableInputDevices()

        let selectedUID = settings.preferredInputDeviceUID
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !selectedUID.isEmpty, !availableInputDevices.contains(where: { $0.id == selectedUID }) {
            settings.preferredInputDeviceUID = ""
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func menuRowButton(
        title: String,
        systemImage: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 13, alignment: .center)
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))

                Spacer()

                if let shortcut, !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 0.6)
            .padding(.horizontal, 2)
    }
}

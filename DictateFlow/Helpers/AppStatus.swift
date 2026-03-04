import SwiftUI

enum AppStatus: Equatable {
    case ready
    case recording
    case transcribing
    case postProcessing
    case failed

    var label: String {
        switch self {
        case .ready:
            return "Bereit"
        case .recording:
            return "Aufnahme läuft"
        case .transcribing:
            return "Verarbeitung…"
        case .postProcessing:
            return "KI-Bearbeitung…"
        case .failed:
            return "Fehler"
        }
    }

    var iconName: String {
        switch self {
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

    var bannerColor: Color {
        switch self {
        case .ready:
            return .green
        case .recording:
            return .red
        case .transcribing:
            return .orange
        case .postProcessing:
            return .blue
        case .failed:
            return .pink
        }
    }
}

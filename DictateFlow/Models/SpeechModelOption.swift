import Foundation

enum SpeechModelOption: String, CaseIterable, Codable, Identifiable {
    case parakeetV3
    case whisperTiny
    case whisperBase
    case whisperSmall
    case whisperMedium
    case whisperLargeV3Turbo
    case whisperLargeV3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parakeetV3:
            return "Parakeet v3"
        case .whisperTiny:
            return "Whisper Tiny"
        case .whisperBase:
            return "Whisper Base"
        case .whisperSmall:
            return "Whisper Small"
        case .whisperMedium:
            return "Whisper Medium"
        case .whisperLargeV3Turbo:
            return "Whisper Large v3 Turbo"
        case .whisperLargeV3:
            return "Whisper Large v3"
        }
    }

    var sizeLabel: String {
        switch self {
        case .parakeetV3:
            return "~2.2 GB"
        case .whisperTiny:
            return "~75 MB"
        case .whisperBase:
            return "~142 MB"
        case .whisperSmall:
            return "~466 MB"
        case .whisperMedium:
            return "~1.5 GB"
        case .whisperLargeV3Turbo:
            return "~1.5 GB"
        case .whisperLargeV3:
            return "~3.1 GB"
        }
    }

    var speedLabel: String {
        switch self {
        case .parakeetV3:
            return "Sehr hoch"
        case .whisperTiny:
            return "Extrem hoch"
        case .whisperBase:
            return "Hoch"
        case .whisperSmall:
            return "Mittel-Hoch"
        case .whisperMedium:
            return "Mittel"
        case .whisperLargeV3Turbo:
            return "Mittel"
        case .whisperLargeV3:
            return "Niedriger"
        }
    }

    var accuracyLabel: String {
        switch self {
        case .parakeetV3:
            return "Sehr hoch"
        case .whisperTiny:
            return "Niedrig"
        case .whisperBase:
            return "Mittel"
        case .whisperSmall:
            return "Hoch"
        case .whisperMedium:
            return "Sehr hoch"
        case .whisperLargeV3Turbo:
            return "Sehr hoch"
        case .whisperLargeV3:
            return "Maximal"
        }
    }

    var details: String {
        switch self {
        case .parakeetV3:
            return "Parakeet-Profileinstellung. Bis native Parakeet-Integration aktiv ist, wird lokal Whisper Large v3 Turbo verwendet."
        case .whisperTiny:
            return "Schnellster Modus, geeignet für kurze Notizen mit geringeren Qualitätsansprüchen."
        case .whisperBase:
            return "Gute Balance für einfache Diktate."
        case .whisperSmall:
            return "Empfohlen für Deutsch und viele europäische Sprachen."
        case .whisperMedium:
            return "Empfohlen für Japanisch/Chinesisch oder höhere Qualität."
        case .whisperLargeV3Turbo:
            return "Hohe Genauigkeit bei besserer Laufzeit als Large v3."
        case .whisperLargeV3:
            return "Maximale Genauigkeit, braucht mehr RAM und Zeit."
        }
    }

    var runtimeWhisperModel: WhisperModel {
        switch self {
        case .parakeetV3:
            return .largeV3Turbo
        case .whisperTiny:
            return .tiny
        case .whisperBase:
            return .base
        case .whisperSmall:
            return .small
        case .whisperMedium:
            return .medium
        case .whisperLargeV3Turbo:
            return .largeV3Turbo
        case .whisperLargeV3:
            return .largeV3
        }
    }

    static func from(whisperModel: WhisperModel) -> SpeechModelOption {
        switch whisperModel {
        case .tiny:
            return .whisperTiny
        case .base:
            return .whisperBase
        case .small:
            return .whisperSmall
        case .medium:
            return .whisperMedium
        case .largeV3Turbo:
            return .whisperLargeV3Turbo
        case .largeV3:
            return .whisperLargeV3
        }
    }
}

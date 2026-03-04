import Foundation

enum TranscriptionLanguage: String, CaseIterable, Codable, Identifiable, Hashable {
    case auto
    case de
    case en
    case fr
    case es
    case it
    case pt
    case nl
    case pl
    case cs
    case sv
    case da
    case no
    case fi
    case tr
    case uk
    case ru
    case ja
    case zh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Automatisch"
        case .de: return "Deutsch"
        case .en: return "Englisch"
        case .fr: return "Französisch"
        case .es: return "Spanisch"
        case .it: return "Italienisch"
        case .pt: return "Portugiesisch"
        case .nl: return "Niederländisch"
        case .pl: return "Polnisch"
        case .cs: return "Tschechisch"
        case .sv: return "Schwedisch"
        case .da: return "Dänisch"
        case .no: return "Norwegisch"
        case .fi: return "Finnisch"
        case .tr: return "Türkisch"
        case .uk: return "Ukrainisch"
        case .ru: return "Russisch"
        case .ja: return "Japanisch"
        case .zh: return "Chinesisch"
        }
    }

    var whisperCode: String? {
        switch self {
        case .auto:
            return nil
        default:
            return rawValue
        }
    }

    static var fallbackChoices: [TranscriptionLanguage] {
        allCases.filter { $0 != .auto }
    }
}

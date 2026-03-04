import Foundation

enum DictationMode: String, CaseIterable, Codable, Identifiable {
    case plain
    case aiPrompt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plain:
            return "Reines Diktat"
        case .aiPrompt:
            return "KI-Umformulierung"
        }
    }

    var descriptionText: String {
        switch self {
        case .plain:
            return "Transkript wird 1:1 in die Zwischenablage gelegt."
        case .aiPrompt:
            return "Transkript wird mit Prompt-Stil lokal umformuliert."
        }
    }
}

enum PromptStyle: String, CaseIterable, Codable, Identifiable {
    case professional
    case business
    case slang
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .professional:
            return "Professionell"
        case .business:
            return "Business-like"
        case .slang:
            return "Slang"
        case .custom:
            return "Benutzerdefiniert"
        }
    }

    var instruction: String {
        switch self {
        case .professional:
            return "Formuliere professionell, präzise und neutral."
        case .business:
            return "Formuliere geschäftlich, strukturiert und zielorientiert."
        case .slang:
            return "Formuliere locker, umgangssprachlich und modern."
        case .custom:
            return ""
        }
    }
}

import Foundation

enum Profile: String, CaseIterable, Codable, Identifiable {
    case email
    case ticket
    case meetingNote
    case reminders

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .email:
            return "E-Mail"
        case .ticket:
            return "Ticket"
        case .meetingNote:
            return "Meetingnotiz"
        case .reminders:
            return "Erinnerungen niederschreiben"
        }
    }

    var systemImage: String {
        switch self {
        case .email:
            return "envelope"
        case .ticket:
            return "ticket"
        case .meetingNote:
            return "person.2"
        case .reminders:
            return "checklist"
        }
    }

    var llmHint: String {
        switch self {
        case .email:
            return "Erzeuge eine präzise, höfliche E-Mail mit klarem Ziel und Abschluss."
        case .ticket:
            return "Erzeuge ein technisches Ticket mit Problem, Reproduktion, Auswirkung und nächstem Schritt."
        case .meetingNote:
            return "Erzeuge strukturierte Meetingnotizen mit Entscheidungen, Aufgaben und Verantwortlichkeiten."
        case .reminders:
            return "Erzeuge klare Erinnerungen mit kurzen, konkreten To-dos und optionalem Zeitbezug."
        }
    }
}

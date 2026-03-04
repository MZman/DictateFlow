import Foundation

struct Transcription: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var profile: Profile
    var rawText: String
    var processedText: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        profile: Profile,
        rawText: String,
        processedText: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.profile = profile
        self.rawText = rawText
        self.processedText = processedText
    }

    var displayText: String {
        let trimmed = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? rawText : processedText
    }
}

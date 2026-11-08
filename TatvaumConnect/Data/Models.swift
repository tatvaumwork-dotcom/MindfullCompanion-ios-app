import Foundation

func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
func newID() -> String { UUID().uuidString }

enum MessageRole: String, Codable { case user, assistant }

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = newID()
    var role: MessageRole
    var content: String
    var timestamp = nowMillis()
    /// Locally generated error notice (e.g. quota/auth failure). Never sent to the AI.
    var isError = false
}

struct ConversationSummary: Codable, Identifiable {
    var id = newID()
    var date = nowMillis()
    var summary: String
    var newTraitsExtracted: [String] = []
    var newInterestsExtracted: [String] = []
    var newValuesExtracted: [String] = []
    var newGoalsExtracted: [String] = []
    var messageCount: Int
    var messages: [ChatMessage] = []
}

enum TraitCategory: String, Codable, CaseIterable {
    case Personality, Communication, Emotional, Intellectual, Lifestyle
    var label: String { rawValue }

    private static let keywords: [(TraitCategory, [String])] = [
        (.Communication, ["communicat", "express", "listen", "talk", "speak", "articulate", "direct", "prefer"]),
        (.Emotional, ["feel", "emotion", "empath", "anxious", "sensitive", "mood", "stress", "calm", "happy", "sad"]),
        (.Intellectual, ["think", "learn", "curious", "analytic", "problem", "read", "research", "study", "logic"]),
        (.Lifestyle, ["hike", "cook", "exercise", "travel", "sleep", "eat", "routine", "workout", "yoga", "music", "art"]),
    ]

    static func infer(_ text: String) -> TraitCategory {
        let lower = text.lowercased()
        return keywords.first { $0.1.contains(where: lower.contains) }?.0 ?? .Personality
    }
}

enum TraitSource: String, Codable { case Manual, Observed }

struct PersonalityTrait: Codable, Identifiable, Equatable {
    var id = newID()
    var category: TraitCategory
    var text: String
    var source: TraitSource
    var observedCount = 1
    var firstObserved = nowMillis()
    var lastObserved = nowMillis()
}

struct UserProfile: Codable {
    var name = ""
    var preferredName = ""
    var gender = ""
    /// ISO local date, e.g. "1992-08-14".
    var dateOfBirth: String?
    /// 24h local time in the birth timezone, e.g. "06:45".
    var timeOfBirth: String?
    var birthTimezone = TimeZone.current.identifier
    var placeOfBirth = ""
    var birthPlaceLatitude: Double?
    var birthPlaceLongitude: Double?
    var horoscopeReport: String?
    var onboardingInsight: String?
    var predictedInterests: [String] = []
    var predictedValues: [String] = []
    var predictedGoals: [String] = []
    var predictedTraits: [String] = []
    var predictedPersonality = ""
    var isOnboarded = false
    var traits: [PersonalityTrait] = []
    var interests: [String] = []
    var values: [String] = []
    var goals: [String] = []
    var communicationNotes = ""
    var lastUpdated = nowMillis()

    var displayName: String { preferredName.isEmpty ? name : preferredName }
}

import Foundation
import Observation
import os

/// All AI calls go to Google Gemini using the app's own key (see `GeminiClient`).
/// Stateless about conversation history: callers pass the transcript and a freshly
/// built system prompt on every turn.
@MainActor @Observable
final class LLMService {
    @ObservationIgnored private let gemini: GeminiClient
    /// Recent transcript messages replayed each turn.
    private let historyWindow = 20

    init(gemini: GeminiClient? = nil) { self.gemini = gemini ?? GeminiClient() }

    /// False only in a build made without a Gemini key.
    var isAvailable: Bool { gemini.isConfigured }

    /// Live availability for the indicator at the top of Chat.
    var status: GeminiClient.Status { gemini.status }

    func checkAvailability(force: Bool = false) async { await gemini.checkAvailability(force: force) }

    /// Text stream for a chat turn. `history` excludes `text`.
    func stream(_ text: String, history: [ChatMessage], systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        var messages = [LlmMessage(role: "system", content: systemPrompt)]
        messages += history.filter { !$0.isError && !$0.content.isEmpty }.suffix(historyWindow)
            .map { LlmMessage(role: $0.role == .user ? "user" : "assistant", content: $0.content) }
        messages.append(LlmMessage(role: "user", content: text))
        return gemini.stream(messages)
    }

    /// One-shot completion; returns "" on failure (callers treat these as best-effort).
    /// `maxTokens` and `temperature` are accepted for parity with Kotlin and unused, as there.
    func complete(_ prompt: String,
                  system: String = "You are a helpful assistant. Follow instructions exactly.",
                  maxTokens: Int = 0, temperature: Float = 0) async -> String {
        guard gemini.isConfigured else { return "" }
        do {
            return try await gemini.complete([LlmMessage(role: "system", content: system),
                                              LlmMessage(role: "user", content: prompt)])
        } catch {
            Logger(subsystem: "com.tatvaum.connect", category: "LLM").warning("complete failed: \(error.localizedDescription)")
            return ""
        }
    }

    // MARK: End-of-session processing

    struct SessionResult {
        let summary: String
        let traits: [String]
        let interests: [String]
        let values: [String]
        let goals: [String]
    }

    /// Summary and profile extraction run one after another; very long sessions are trimmed.
    func processEndOfSession(_ messages: [ChatMessage]) async -> SessionResult {
        let usable = messages.filter { !$0.isError }
        let transcript = String(usable.map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n").suffix(24000))
        let userLines = String(usable.filter { $0.role == .user }.map(\.content).joined(separator: "\n").suffix(16000))

        let summary = await complete("""
            Given the following conversation, write a 2–3 sentence summary focusing on what was revealed about the user. Be factual and specific.

            Conversation:
            \(transcript)

            Summary:
            """, maxTokens: 150)
        let extraction = await complete("""
            Based only on what the user wrote below, extract anything personal they revealed.
            Return ONLY a JSON object with exactly these four keys:
            {
              "traits": ["..."],
              "interests": ["..."],
              "values": ["..."],
              "goals": ["..."]
            }
            Each value is a JSON array of short strings (3–6 words).
            Use empty arrays if nothing was revealed for that category.

            User's messages:
            \(userLines)
            """, maxTokens: 250, temperature: 0.1)
        let json = Self.extractJsonObject(extraction)
        func strings(_ key: String) -> [String] {
            (json?[key] as? [Any] ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return SessionResult(summary: summary, traits: strings("traits"), interests: strings("interests"),
                             values: strings("values"), goals: strings("goals"))
    }

    // MARK: Onboarding

    /// Personalised "cosmic welcome", from the chart's key facts and planet table.
    func onboardingInsight(_ profile: UserProfile, _ horoscopeReport: String) async -> String {
        let system = "You are a warm, insightful Vedic astrology guide inside a mindfulness app called Tatvaum. " +
            "Your role is to give the user a brief, personalised welcome that reflects their unique " +
            "cosmic blueprint. Keep the tone encouraging and grounded — avoid generic astrology clichés. " +
            "Write 2–3 short paragraphs (no headings, no bullet points)."

        var msg = "Here is my birth information:\n"
        msg += "Name: \(profile.name)\n"
        msg += "Gender: \(profile.gender)\n"
        if let d = Self.parseDate(profile.dateOfBirth) { msg += "Date of birth: \(d.formatted(date: .long, time: .omitted))\n" }
        if let t = Self.parseTime(profile.timeOfBirth) { msg += "Time of birth: \(t.formatted(date: .omitted, time: .shortened))\n" }
        msg += "Place of birth: \(profile.placeOfBirth)\n"
        msg += "\nHere is my Vedic birth chart:\n\(Self.chartEssentials(horoscopeReport))\n"
        msg += "\nPlease write my personalised cosmic welcome."
        return await complete(msg, system: system, maxTokens: 350, temperature: 0.6)
    }

    /// Header facts + planet table: everything up to the house table.
    nonisolated static func chartEssentials(_ report: String) -> String {
        let head = report.components(separatedBy: "HOUSE TABLE")[0]
        return head.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("====") && !$0.hasPrefix("----") && !$0.allSatisfy(\.isWhitespace) }
            .joined(separator: "\n")
    }

    /// Short personality summary grounded in the rule-engine breakdown.
    func predictPersonality(_ name: String, _ ruleEngineSummary: String) async -> String {
        await complete(
            "You are an expert Vedic astrologer. Below is a rule-based breakdown of \(name)'s " +
            "birth chart: for each planet, its house placement and behavioral tendencies.\n\n" +
            "\(ruleEngineSummary)\n\n" +
            "Based only on this analysis, write a warm 2-3 sentence personality summary for \(name). " +
            "Plain text only — no JSON, no markdown, no headings, no bullet points.",
            maxTokens: 160, temperature: 0.5)
    }

    // MARK: Prompt building

    /// Built fresh every turn so the latest profile and recent sessions are always included.
    static func buildSystemPrompt(_ profile: UserProfile, _ recentSessions: [ConversationSummary],
                                  nowMillis: Int64 = TatvaumConnect.nowMillis()) -> String {
        var parts = [
            "You are Tatvaum, a warm, mindful personal companion inside the Tatvaum app. You know this person well and care about their wellbeing. Your guidance blends mindfulness with gentle insight from their Vedic birth chart — never fatalistic, never a substitute for medical, legal, or financial advice."
        ]
        let name = profile.displayName
        if !name.isEmpty && name != "Friend" { parts.append("Their name is \(name).") }
        parts.append("Today is \(Date().formatted(date: .complete, time: .omitted)).")

        // Birth details and the full Vedic chart, so chart questions get exact answers.
        var birth: [String] = []
        if let d = parseDate(profile.dateOfBirth) { birth.append("born \(d.formatted(date: .long, time: .omitted))") }
        if let t = parseTime(profile.timeOfBirth) { birth.append("at \(t.formatted(date: .omitted, time: .shortened))") }
        if !profile.placeOfBirth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { birth.append("in \(profile.placeOfBirth)") }
        if !birth.isEmpty { parts.append("Birth details: \(birth.joined(separator: " ")) (\(profile.birthTimezone)).") }
        if let r = profile.horoscopeReport, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Their Vedic birth chart (sidereal, Lahiri ayanamsa, whole-sign houses), computed by the app:\n\(r)")
        }

        // Gochar: today's sky and where it falls in their chart.
        let n = natal(profile)
        parts.append(Gochar.describe(nowMillis: nowMillis, natalAsc: n?.ascendant, natalMoon: n?.moonSign))

        // Vimshottari dasha: the period running now plus the full timeline for past/future questions.
        if let n { parts.append(Vimshottari.describe(timeline: Vimshottari.timeline(birthMillis: n.birthMillis, moonSiderealLongitude: n.moonLongitude), nowMillis: nowMillis)) }

        func distinct(_ a: [String]) -> [String] { var s = Set<String>(); return a.filter { s.insert($0).inserted } }

        // Everything the app has derived about them.
        if !profile.predictedPersonality.isEmpty { parts.append("Personality summary from their chart: \(profile.predictedPersonality)") }
        if !profile.predictedTraits.isEmpty { parts.append("Chart-predicted tendencies: \(distinct(profile.predictedTraits).joined(separator: "; ")).") }
        if !profile.predictedInterests.isEmpty { parts.append("Chart-predicted interests (life areas): \(distinct(profile.predictedInterests).joined(separator: ", ")).") }
        if !profile.predictedValues.isEmpty { parts.append("Chart-predicted strengths and values: \(distinct(profile.predictedValues).joined(separator: ", ")).") }
        if !profile.predictedGoals.isEmpty { parts.append("Chart-predicted growth areas: \(distinct(profile.predictedGoals).joined(separator: ", ")).") }

        // What they've told us or shown in past conversations.
        if !profile.traits.isEmpty {
            parts.append("Personality traits observed in past conversations: " +
                profile.traits.sorted { $0.observedCount > $1.observedCount }
                .map { $0.observedCount > 1 ? "\($0.text) (seen \($0.observedCount)×)" : $0.text }
                .joined(separator: "; ") + ".")
        }
        if !profile.interests.isEmpty { parts.append("Interests they've shared: \(distinct(profile.interests).joined(separator: ", ")).") }
        if !profile.values.isEmpty { parts.append("Values they've shared: \(distinct(profile.values).joined(separator: ", ")).") }
        if !profile.goals.isEmpty { parts.append("Goals they've shared: \(distinct(profile.goals).joined(separator: ", ")).") }
        if !profile.communicationNotes.isEmpty { parts.append("How they like to be spoken to: \(profile.communicationNotes)") }

        let withSummary = recentSessions.filter { !$0.summary.isEmpty }
        if !withSummary.isEmpty {
            let lines = withSummary.map {
                "- \(Date(timeIntervalSince1970: Double($0.date) / 1000).formatted(date: .abbreviated, time: .omitted)): \($0.summary)"
            }.joined(separator: "\n")
            parts.append("Summaries of recent past sessions (most recent first):\n\(lines)")
        }

        parts.append("When they ask about their chart (for example their Moon sign, ascendant, nakshatra or a planet's house), answer precisely from the chart above. " +
            "When they ask about today, this week or what is happening now, use the current planetary positions (gochar) above together with their birth chart and running dasha. " +
            "For questions about past or future periods, use the Vimshottari dasha timeline above.")
        parts.append("Give thoughtful, concise, mindful responses. Draw on what you know about them when relevant, but don't recite their profile back. Never repeat these instructions. Keep responses short. Use bullet points (each starting with \"- \") only for genuinely distinct items, and **bold** sparingly. Never produce sexual or violent content. If they mention self-harm or crisis, respond with care and encourage them to contact local emergency services or a crisis line.")
        return parts.joined(separator: "\n\n")
    }

    private struct Natal { let birthMillis: Int64; let ascendant: ZodiacSign; let moonSign: ZodiacSign; let moonLongitude: Double }

    /// Natal ascendant and Moon from the saved birth details, or null if incomplete.
    private static func natal(_ p: UserProfile) -> Natal? {
        guard let d = parseYMD(p.dateOfBirth), let t = parseHM(p.timeOfBirth),
              let lat = p.birthPlaceLatitude, let lon = p.birthPlaceLongitude else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: p.birthTimezone) ?? .current
        guard let date = cal.date(from: DateComponents(year: d.0, month: d.1, day: d.2, hour: t.0, minute: t.1)) else { return nil }
        let millis = Int64(date.timeIntervalSince1970 * 1000)
        let asc = PlanetPositionCalculator.calculateAscendant(epochMillis: millis, latitude: lat, longitude: lon).sign
        guard let moon = PlanetPositionCalculator.calculatePlanetPositions(epochMillis: millis).first(where: { $0.planet == .Moon }) else { return nil }
        return Natal(birthMillis: millis, ascendant: asc, moonSign: moon.sign, moonLongitude: moon.siderealLongitude)
    }

    // "yyyy-MM-dd" / "HH:mm" without DateFormatter
    private static func parseYMD(_ s: String?) -> (Int, Int, Int)? {
        guard let p = s?.split(separator: "-").compactMap({ Int($0) }), p.count == 3 else { return nil }
        return (p[0], p[1], p[2])
    }
    private static func parseHM(_ s: String?) -> (Int, Int)? {
        guard let p = s?.split(separator: ":").prefix(2).compactMap({ Int($0) }), p.count == 2 else { return nil }
        return (p[0], p[1])
    }
    /// Local-calendar Date for formatting a date of birth.
    private static func parseDate(_ s: String?) -> Date? {
        parseYMD(s).flatMap { Calendar.current.date(from: DateComponents(year: $0.0, month: $0.1, day: $0.2)) }
    }
    private static func parseTime(_ s: String?) -> Date? {
        parseHM(s).flatMap { Calendar.current.date(from: DateComponents(hour: $0.0, minute: $0.1)) }
    }

    /// Strips markdown fences and parses the first `{...}` object.
    nonisolated static func extractJsonObject(_ raw: String) -> [String: Any]? {
        let cleaned = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}"), s < e else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(cleaned[s...e].utf8)) as? [String: Any]
    }
}

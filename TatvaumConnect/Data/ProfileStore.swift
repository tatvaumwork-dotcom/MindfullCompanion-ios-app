import Foundation
import Observation
import os

enum ListKind { case interests, values, goals }

/// Owns the user profile. All mutation happens on the main actor.
@MainActor @Observable
final class ProfileStore {
    private(set) var profile: UserProfile
    private(set) var isGeneratingPredictions = false

    @ObservationIgnored private let file = JSONFile<UserProfile>("profile.json")
    @ObservationIgnored private let llm: LLMService
    @ObservationIgnored private let ruleEngine: RuleEngine

    init(llm: LLMService, ruleEngine: RuleEngine) {
        self.llm = llm
        self.ruleEngine = ruleEngine
        profile = file.read() ?? UserProfile()
    }

    private func update(_ transform: (inout UserProfile) -> Void) {
        transform(&profile)
        profile.lastUpdated = nowMillis()
        let snapshot = profile, file = file
        writerQueue.async { file.write(snapshot) }
    }

    // MARK: Onboarding

    func completeOnboarding(name: String, preferredName: String, gender: String, dateOfBirth: Date, timeOfBirth: Date,
                            timezone: String, placeOfBirth: String, latitude: Double?, longitude: Double?) {
        let tz = TimeZone(identifier: timezone) ?? .current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        update {
            $0.name = name
            $0.preferredName = preferredName.isEmpty ? name : preferredName
            $0.gender = gender
            $0.dateOfBirth = Self.isoDate(dateOfBirth, cal)
            $0.timeOfBirth = Self.hhmm(timeOfBirth, cal)
            $0.birthTimezone = timezone
            $0.placeOfBirth = placeOfBirth
            $0.birthPlaceLatitude = latitude
            $0.birthPlaceLongitude = longitude
            $0.isOnboarded = true
        }
        runChartPipeline(includeWelcome: true)
    }

    func resetOnboarding() {
        update {
            $0.isOnboarded = false; $0.name = ""; $0.preferredName = ""; $0.gender = ""
            $0.dateOfBirth = nil; $0.timeOfBirth = nil; $0.birthTimezone = TimeZone.current.identifier
            $0.placeOfBirth = ""; $0.birthPlaceLatitude = nil; $0.birthPlaceLongitude = nil
            $0.horoscopeReport = nil
        }
    }

    /// Also writes the cosmic welcome if it's missing (e.g. the AI was unreachable at onboarding).
    func regeneratePredictions() { runChartPipeline(includeWelcome: (profile.onboardingInsight ?? "").isEmpty) }

    /// Chart → (optional) AI cosmic welcome → deterministic rule-engine traits/interests/values/goals → AI personality summary.
    private func runChartPipeline(includeWelcome: Bool) {
        let p = profile
        guard let lat = p.birthPlaceLatitude, let lon = p.birthPlaceLongitude,
              let dob = p.dateOfBirth, let tob = p.timeOfBirth, !isGeneratingPredictions,
              let birthMillis = Self.birthMillis(dob, tob, p.birthTimezone) else { return }
        isGeneratingPredictions = true
        let engine = ruleEngine
        Task {
            defer { isGeneratingPredictions = false }
            let (report, prediction) = await Task.detached(priority: .userInitiated) {
                let chart = HoroscopeCalculator.generate(name: p.name, gender: p.gender, birthMillis: birthMillis, latitude: lat, longitude: lon)
                return (HoroscopeCalculator.textReport(chart), engine.predict(chart))
            }.value
            update { $0.horoscopeReport = report }

            if includeWelcome {
                let insight = await llm.onboardingInsight(profile, report)
                if !insight.isEmpty { update { $0.onboardingInsight = insight } }
            }
            // Show the deterministic predictions immediately; personality follows.
            update {
                $0.predictedTraits = prediction.traits; $0.predictedInterests = prediction.interests
                $0.predictedValues = prediction.values; $0.predictedGoals = prediction.goals
            }
            let personality = await llm.predictPersonality(p.name, prediction.summary)
            if !personality.isEmpty { update { $0.predictedPersonality = personality } }
        }
    }

    // MARK: Identity

    func setName(_ name: String) { update { $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines) } }
    func setCommunicationNotes(_ notes: String) { update { $0.communicationNotes = notes } }

    // MARK: Traits

    func addTrait(_ t: PersonalityTrait) { update { $0.traits.append(t) } }
    func updateTrait(_ t: PersonalityTrait) { update { if let i = $0.traits.firstIndex(where: { $0.id == t.id }) { $0.traits[i] = t } } }
    func deleteTrait(_ id: String) { update { $0.traits.removeAll { $0.id == id } } }

    /// Increments observedCount on case-insensitive duplicates, appends new ones as Observed.
    func mergeExtractedTraits(_ texts: [String]) {
        let cleaned = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        update { p in
            let now = nowMillis()
            for text in cleaned {
                if let i = p.traits.firstIndex(where: { $0.text.caseInsensitiveCompare(text) == .orderedSame }) {
                    p.traits[i].observedCount += 1; p.traits[i].lastObserved = now
                } else {
                    p.traits.append(PersonalityTrait(category: .infer(text), text: text, source: .Observed))
                }
            }
        }
    }

    // MARK: Lists

    func addItem(_ kind: ListKind, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        update { p in
            let path = Self.path(kind)
            if !p[keyPath: path].contains(t) { p[keyPath: path].append(t) }
        }
    }

    func removeItem(_ kind: ListKind, _ text: String) { update { $0[keyPath: Self.path(kind)].removeAll { $0 == text } } }

    // MARK: Helpers

    private static func path(_ k: ListKind) -> WritableKeyPath<UserProfile, [String]> {
        switch k { case .interests: \.interests; case .values: \.values; case .goals: \.goals }
    }

    private static func isoDate(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private static func hhmm(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    /// Birth instant (epoch ms) from local date/time strings in the birth timezone.
    nonisolated static func birthMillis(_ dob: String, _ tob: String, _ tz: String) -> Int64? {
        let d = dob.split(separator: "-").compactMap { Int($0) }, t = tob.split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count >= 2 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz) ?? .current
        guard let date = cal.date(from: DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1])) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}

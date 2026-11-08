import Foundation
import Observation

/// One week's third-eye question and the person's reflection on it.
struct ThirdEyeEntry: Codable, Equatable {
    /// ISO date (yyyy-MM-dd) of the Monday this question belongs to.
    var weekStart: String
    var question: String
    var answer: String = ""
    var answeredAt: Int64?
}

/// Weekly "third-eye" questions: a new one every Monday at 7:00, kept for the whole week.
/// Each install gets its own random order of the pool, so no question repeats until all are asked.
enum ThirdEye {
    static let arrivalHour = 7

    /// Monday 00:00 of the week containing `day` (Calendar.current, Monday-based).
    private static func monday(of day: Date, _ cal: Calendar) -> Date {
        let start = cal.startOfDay(for: day)
        return cal.date(byAdding: .day, value: -((cal.component(.weekday, from: start) + 5) % 7), to: start)!
    }

    private static let epochMonday = DateComponents(calendar: .current, year: 2024, month: 1, day: 1).date!

    /// The Monday whose question is current at `now` (before Monday 7:00 it's still last week's).
    static func weekStart(now: Date = .now, calendar cal: Calendar = .current) -> Date {
        let mon = monday(of: now, cal)
        let arrival = cal.date(bySettingHour: arrivalHour, minute: 0, second: 0, of: mon)!
        return now < arrival ? cal.date(byAdding: .day, value: -7, to: mon)! : mon
    }

    /// When the next question arrives.
    static func nextArrival(now: Date = .now, calendar cal: Calendar = .current) -> Date {
        let next = cal.date(byAdding: .day, value: 7, to: weekStart(now: now, calendar: cal))!
        return cal.date(bySettingHour: arrivalHour, minute: 0, second: 0, of: next)!
    }

    /// yyyy-MM-dd key for a week start, as stored in `ThirdEyeEntry.weekStart`.
    static func key(_ date: Date, calendar cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func date(fromKey key: String, calendar cal: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return DateComponents(calendar: cal, year: p[0], month: p[1], day: p[2]).date
    }

    /// The question for a given week, from this install's shuffled order.
    static func questionFor(week: Date, seed: UInt64, calendar cal: Calendar = .current) -> String {
        var rng = SplitMix64(state: seed)
        let order = QUESTIONS.indices.shuffled(using: &rng)
        let days = cal.dateComponents([.day], from: epochMonday, to: cal.startOfDay(for: week)).day!
        let weeks = Int((Double(days) / 7).rounded(.down))
        return QUESTIONS[order[((weeks % QUESTIONS.count) + QUESTIONS.count) % QUESTIONS.count]]
    }

    /// Reflective, playful questions: one a week, a little over a year's worth.
    static let QUESTIONS = [
        "If your soul sent you a text this morning, what would it say?",
        "What are you pretending not to know right now?",
        "Which small habit is quietly shaping your future the most?",
        "What would you do this week if you knew you couldn't fail?",
        "Who brings out the softest version of you, and have you told them?",
        "What is one thing you're carrying that was never yours to carry?",
        "When did you last feel completely at home in yourself?",
        "What does your body keep trying to tell you?",
        "Which fear has been making your decisions lately?",
        "What would your eight-year-old self be proud of in you today?",
        "What are you rushing that deserves patience?",
        "If this week had a colour, what would it be and why?",
        "What conversation have you been avoiding, and what's it costing you?",
        "Where in your life are you saying yes when you mean no?",
        "What made you lose track of time recently?",
        "Which of your 'flaws' is secretly a strength?",
        "What would change if you trusted your intuition a little more?",
        "What do you need to forgive yourself for?",
        "If the stars wrote you a note, what would they want you to remember?",
        "What is quietly going well that you haven't celebrated?",
        "Who are you becoming, and do you like them?",
        "What story about yourself are you ready to stop telling?",
        "Where do you feel most alive, and how can you go there more often?",
        "What are you grateful for that you usually overlook?",
        "What boundary would make your life lighter this week?",
        "What is your heart curious about right now?",
        "What would you attempt if no one was watching?",
        "Which relationship deserves more of your presence?",
        "What did a recent disappointment teach you?",
        "When do you feel most like the moon, and when most like the sun?",
        "What does 'enough' look like for you right now?",
        "What is one kind thing you can do for your future self today?",
        "What pattern keeps showing up in your life, and what is it asking of you?",
        "Where are you holding your breath, literally or otherwise?",
        "What would you like to be remembered for this week?",
        "What feels heavy, and what would make it a little lighter?",
        "Which part of you needs more rest, and which part needs more play?",
        "What truth are you finally ready to say out loud?",
        "If you could whisper advice to yourself a year ago, what would it be?",
        "What brings you peace that costs nothing?",
        "Who inspires you lately, and what quality of theirs do you share?",
        "What are you outgrowing?",
        "What would make this week feel meaningful, even if it's ordinary?",
        "Where is your energy leaking, and where is it flowing?",
        "What is your intuition saying about a decision you're facing?",
        "What does your ideal quiet morning look like?",
        "What are you holding onto just because it's familiar?",
        "What has been surprisingly beautiful lately?",
        "If your life were a season right now, which one would it be?",
        "What gift do you bring to every room you enter?",
        "What would it feel like to be fully on your own side this week?",
        "What question do you wish someone would ask you?",
        "What are you ready to welcome in?",
    ]
}

/// Deterministic generator so a seed always yields the same question order.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Keeps every week's question and answer; makes sure the current week's question exists.
@MainActor @Observable
final class ThirdEyeStore {
    private let file: JSONFile<[ThirdEyeEntry]>
    private let now: () -> Date

    /// This install's random question order.
    let seed: UInt64

    /// Newest first.
    private(set) var entries: [ThirdEyeEntry]

    init(fileName: String = "third_eye.json", defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now }) {
        file = JSONFile(fileName)
        self.now = now
        let saved = UInt64(bitPattern: Int64(defaults.integer(forKey: "third_eye_seed")))
        if saved != 0 { seed = saved } else {
            seed = UInt64.random(in: 1...UInt64(Int64.max))
            defaults.set(Int(seed), forKey: "third_eye_seed")
        }
        entries = (file.read() ?? []).sorted { $0.weekStart > $1.weekStart }
    }

    /// Adds this week's question if it isn't there yet and returns it.
    @discardableResult
    func current() -> ThirdEyeEntry {
        let weekDate = ThirdEye.weekStart(now: now())
        let week = ThirdEye.key(weekDate)
        if let e = entries.first(where: { $0.weekStart == week }) { return e }
        let entry = ThirdEyeEntry(weekStart: week, question: ThirdEye.questionFor(week: weekDate, seed: seed))
        entries = ([entry] + entries).sorted { $0.weekStart > $1.weekStart }
        save()
        return entry
    }

    func saveAnswer(weekStart: String, answer: String) {
        guard let i = entries.firstIndex(where: { $0.weekStart == weekStart }) else { return }
        entries[i].answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[i].answeredAt = nowMillis()
        save()
    }

    private func save() {
        let snapshot = entries, file = file
        writerQueue.async { file.write(snapshot) }
    }
}

import Foundation
import Testing
@testable import TatvaumConnect

struct ThirdEyeTests {
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        DateComponents(calendar: .current, year: y, month: m, day: d, hour: h, minute: min).date!
    }

    @Test func bankHasAllQuestions() {
        #expect(ThirdEye.QUESTIONS.count == 53)
        #expect(Set(ThirdEye.QUESTIONS).count == 53)
    }

    @Test func weekStartRollsOverMondayAtSeven() {
        // 2024-01-01 is a Monday.
        #expect(ThirdEye.key(ThirdEye.weekStart(now: at(2024, 1, 1, 6, 59))) == "2023-12-25")
        #expect(ThirdEye.key(ThirdEye.weekStart(now: at(2024, 1, 1, 7, 0))) == "2024-01-01")
        #expect(ThirdEye.key(ThirdEye.weekStart(now: at(2024, 1, 7, 23, 0))) == "2024-01-01")
        #expect(ThirdEye.key(ThirdEye.weekStart(now: at(2024, 1, 8, 6, 0))) == "2024-01-01")
        #expect(ThirdEye.nextArrival(now: at(2024, 1, 3)) == at(2024, 1, 8, 7))
    }

    @Test func questionsCycleWithoutRepeatAndAreDeterministic() {
        let seed: UInt64 = 42
        let n = ThirdEye.QUESTIONS.count
        let weeks = (0..<n).map { ThirdEye.questionFor(week: at(2024, 1, 1 + 7 * $0), seed: seed) }
        #expect(Set(weeks).count == n)
        #expect(ThirdEye.questionFor(week: at(2024, 1, 1 + 7 * n), seed: seed) == weeks[0])
        #expect(ThirdEye.questionFor(week: at(2023, 12, 25), seed: seed) == weeks[n - 1])
        #expect(ThirdEye.questionFor(week: at(2024, 1, 1), seed: seed) == weeks[0])
    }

    @MainActor @Test func storeAddsCurrentOnceAndSavesAnswer() {
        let name = "te-test-\(UUID().uuidString).json"
        let defaults = UserDefaults(suiteName: name)!
        var now = at(2024, 3, 6)
        let store = ThirdEyeStore(fileName: name, defaults: defaults, now: { now })
        let a = store.current()
        #expect(a.weekStart == "2024-03-04")
        #expect(store.current() == a && store.entries.count == 1)
        store.saveAnswer(weekStart: a.weekStart, answer: "  hi \n")
        #expect(store.entries[0].answer == "hi" && store.entries[0].answeredAt != nil)
        now = at(2024, 3, 12)
        store.current()
        #expect(store.entries.map(\.weekStart) == ["2024-03-11", "2024-03-04"])
        #expect(ThirdEyeStore(fileName: name, defaults: defaults).seed == store.seed)
        JSONFile<[ThirdEyeEntry]>(name).delete()
    }
}

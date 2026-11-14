import Foundation
import WidgetKit

/// What the Third Eye widget shows, shared through the app group. Keep in sync with
/// TatvaumWidget/ThirdEyeWidget.swift, which decodes the same JSON.
struct ThirdEyeWidgetData: Codable {
    struct Week: Codable {
        /// yyyy-MM-dd of the week's Monday.
        var weekStart: String
        /// When this week's question arrives (Monday 7:00), seconds since 1970.
        var arrival: Double
        var question: String
    }
    /// The current week first, then the next few, so the widget can roll over on its own.
    var weeks: [Week]
    /// Weeks that have a saved reflection.
    var answered: [String]
}

enum ThirdEyeWidgetBridge {
    static let appGroup = "group.com.tatvaum.connect"
    static let key = "third_eye_widget"
    private static let weeksAhead = 12

    /// Writes the current and upcoming questions for the widget and asks WidgetKit to redraw it.
    @MainActor static func publish(_ store: ThirdEyeStore, now: Date = .now) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let cal = Calendar.current
        let current = ThirdEye.weekStart(now: now)
        let weeks = (0..<weeksAhead).map { k -> ThirdEyeWidgetData.Week in
            let week = cal.date(byAdding: .day, value: 7 * k, to: current)!
            let key = ThirdEye.key(week)
            let arrival = cal.date(bySettingHour: ThirdEye.arrivalHour, minute: 0, second: 0, of: week)!
            let question = store.entries.first { $0.weekStart == key }?.question ?? ThirdEye.questionFor(week: week, seed: store.seed)
            return .init(weekStart: key, arrival: arrival.timeIntervalSince1970, question: question)
        }
        let answered = store.entries.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.weekStart)
        guard let data = try? JSONEncoder().encode(ThirdEyeWidgetData(weeks: weeks, answered: answered)) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

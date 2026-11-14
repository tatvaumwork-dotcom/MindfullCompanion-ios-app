import SwiftUI
import WidgetKit

/// Mirrors ThirdEyeWidgetData in the app (TatvaumConnect/ThirdEye/ThirdEyeWidgetBridge.swift).
private struct WidgetData: Codable {
    struct Week: Codable { var weekStart: String; var arrival: Double; var question: String }
    var weeks: [Week]
    var answered: [String]

    static func load() -> WidgetData? {
        guard let data = UserDefaults(suiteName: "group.com.tatvaum.connect")?.data(forKey: "third_eye_widget") else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }
}

struct ThirdEyeEntry: TimelineEntry {
    let date: Date
    /// nil until the app has been opened once.
    let question: String?
    let weekStart: Date?
    let answered: Bool
}

struct ThirdEyeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ThirdEyeEntry {
        ThirdEyeEntry(date: .now, question: "If your soul sent you a text this morning, what would it say?", weekStart: .now, answered: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ThirdEyeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(now: .now).first!)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ThirdEyeEntry>) -> Void) {
        let list = entries(now: .now)
        // The app republishes the weeks ahead whenever it opens; refresh daily in case it doesn't.
        completion(Timeline(entries: list, policy: .after(Calendar.current.date(byAdding: .day, value: 1, to: .now)!)))
    }

    /// One entry for the current week (from now) and one at each later week's arrival.
    private func entries(now: Date) -> [ThirdEyeEntry] {
        guard let data = WidgetData.load(), !data.weeks.isEmpty else {
            return [ThirdEyeEntry(date: now, question: nil, weekStart: nil, answered: false)]
        }
        let weeks = data.weeks.sorted { $0.arrival < $1.arrival }
        let currentIndex = weeks.lastIndex { $0.arrival <= now.timeIntervalSince1970 } ?? 0
        return weeks[currentIndex...].enumerated().map { i, w in
            ThirdEyeEntry(date: i == 0 ? now : Date(timeIntervalSince1970: w.arrival), question: w.question,
                          weekStart: Self.date(w.weekStart), answered: data.answered.contains(w.weekStart))
        }
    }

    private static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return DateComponents(calendar: .current, year: p[0], month: p[1], day: p[2]).date
    }
}

private let gold = Color(red: 0xF5 / 255, green: 0xC6 / 255, blue: 0x6B / 255)
private let muted = Color(red: 0x9A / 255, green: 0xA0 / 255, blue: 0xC8 / 255)
private let starText = Color(red: 0xE6 / 255, green: 0xE8 / 255, blue: 0xFF / 255)
private let panel = Color(red: 0x0E / 255, green: 0x10 / 255, blue: 0x20 / 255)

struct ThirdEyeWidgetView: View {
    let entry: ThirdEyeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("👁  THIRD EYE").font(.system(size: 12, weight: .bold)).foregroundStyle(gold)
                Spacer(minLength: 4)
                if let week = entry.weekStart, family != .systemSmall {
                    Text("Week of \(week.formatted(.dateTime.month(.abbreviated).day()))").font(.system(size: 11)).foregroundStyle(muted)
                }
            }
            Text(entry.question ?? "Open Tatvaum to receive this week's question.")
                .font(.system(size: family == .systemSmall ? 14 : 16, weight: .bold)).foregroundStyle(starText)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(entry.answered ? "✦ Reflected · new question Monday" : "✦ Tap to reflect")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(entry.answered ? muted : gold).lineLimit(1)
        }
        .containerBackground(panel, for: .widget)
        .widgetURL(URL(string: "tatvaum://third-eye"))
    }
}

struct ThirdEyeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ThirdEyeWidget", provider: ThirdEyeProvider()) { ThirdEyeWidgetView(entry: $0) }
            .configurationDisplayName("Third Eye")
            .description("This week's reflective question. A new one arrives every Monday.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TatvaumWidgets: WidgetBundle {
    var body: some Widget { ThirdEyeWidget() }
}

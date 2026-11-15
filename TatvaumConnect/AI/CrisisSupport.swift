import Foundation

/// Crisis helplines for the person's region (from the device's region setting), shown when a
/// message suggests they may be thinking of suicide or self-harm.
/// Check these numbers periodically: services occasionally change.
enum CrisisSupport {
    struct Line: Equatable {
        let name: String
        /// Shown to the person, e.g. "14416".
        let display: String
        /// Dialled, e.g. "14416".
        let dial: String
        /// Number that also accepts text messages, if any.
        var sms: String?
    }

    struct Region: Equatable {
        let lines: [Line]
        let emergency: String
    }

    private static let regions: [String: Region] = [
        "IN": Region(lines: [Line(name: "Tele-MANAS (24/7, free)", display: "14416", dial: "14416")], emergency: "112"),
        "US": Region(lines: [Line(name: "988 Suicide & Crisis Lifeline", display: "988", dial: "988", sms: "988")], emergency: "911"),
        "CA": Region(lines: [Line(name: "9-8-8 Suicide Crisis Helpline", display: "988", dial: "988", sms: "988")], emergency: "911"),
        "GB": Region(lines: [Line(name: "Samaritans (24/7, free)", display: "116 123", dial: "116123")], emergency: "999"),
        "IE": Region(lines: [Line(name: "Samaritans (24/7, free)", display: "116 123", dial: "116123")], emergency: "112"),
        "AU": Region(lines: [Line(name: "Lifeline", display: "13 11 14", dial: "131114")], emergency: "000"),
        "NZ": Region(lines: [Line(name: "Need to talk? (call or text)", display: "1737", dial: "1737", sms: "1737")], emergency: "111"),
    ]

    /// Directory of helplines worldwide, for regions not listed above.
    static let directory = URL(string: "https://findahelpline.com")!

    /// Lines for `regionCode` (ISO 3166, e.g. "IN"); nil when we don't list that region.
    static func region(_ regionCode: String? = Locale.current.region?.identifier) -> Region? {
        regionCode.flatMap { regions[$0.uppercased()] }
    }

    /// Plain-text version, saved as the message content (shown in history and session views).
    static func text(regionCode: String? = Locale.current.region?.identifier) -> String {
        var out = "It sounds like you're going through something really painful, and I'm glad you said it. You don't have to face this alone. Please reach out to someone who can help right now:\n"
        if let r = region(regionCode) {
            for l in r.lines { out += "- **\(l.name)**: \(l.display)\(l.sms != nil ? " (call or text)" : "")\n" }
            out += "- **Emergency**: \(r.emergency)\n"
        } else {
            out += "- Your local emergency number\n- Find a free helpline near you at findahelpline.com\n"
        }
        out += "If you're in immediate danger, please call emergency services or go to the nearest hospital."
        return out
    }
}

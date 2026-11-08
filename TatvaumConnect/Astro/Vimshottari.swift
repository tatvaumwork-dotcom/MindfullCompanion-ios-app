import Foundation

/// Vimshottari dasha: the 120-year planetary period system, started from the lord of the birth
/// Moon's nakshatra with the balance left at birth. Mahadashas, antardashas and pratyantardashas with dates.
enum Vimshottari {

    /// Order of the cycle and each lord's mahadasha length in years (total 120).
    static let ORDER: [(planet: VedicPlanet, years: Double)] = [
        (.Ketu, 7), (.Venus, 20), (.Sun, 6), (.Moon, 10), (.Mars, 7),
        (.Rahu, 18), (.Jupiter, 16), (.Saturn, 19), (.Mercury, 17),
    ]
    private static let total = 120.0
    private static let daysPerYear = 365.25
    private static let dayMs = 86_400_000.0

    struct Period: Hashable, Sendable {
        let lord: VedicPlanet
        let startMillis: Int64
        let endMillis: Int64
        var sub: [Period] = []

        func contains(t: Int64) -> Bool { t >= startMillis && t < endMillis }
    }

    /// Snapshot of what is running at a moment.
    struct Current: Sendable {
        let maha: Period
        let antar: Period
        let pratyantar: Period
    }

    private static func years(_ lord: VedicPlanet) -> Double { ORDER.first { $0.planet == lord }!.years }
    private static func indexOf(_ lord: VedicPlanet) -> Int { ORDER.firstIndex { $0.planet == lord }! }

    /// Lord of a nakshatra (Ashwini -> Ketu, Bharani -> Venus, ... repeating every 9).
    static func nakshatraLord(_ nakshatra: Nakshatra) -> VedicPlanet { ORDER[nakshatra.ordinal % 9].planet }

    /// Full mahadasha timeline (one 120-year cycle) from the Moon's sidereal longitude at birth.
    /// The first mahadasha began before birth; only its remaining balance falls after birth.
    static func timeline(birthMillis: Int64, moonSiderealLongitude: Double) -> [Period] {
        let span = 360.0 / 27
        let lon = (moonSiderealLongitude.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let nak = Nakshatra.allCases[Int(lon / span) % 27]
        let traversed = lon.truncatingRemainder(dividingBy: span) / span
        let firstLord = nakshatraLord(nak)
        var start = birthMillis - Int64(traversed * years(firstLord) * daysPerYear * dayMs)
        let start0 = indexOf(firstLord)
        return (0..<9).map { k in
            let lord = ORDER[(start0 + k) % 9].planet
            let end = start + Int64(years(lord) * daysPerYear * dayMs)
            defer { start = end }
            return Period(lord: lord, startMillis: start, endMillis: end,
                          sub: subPeriods(parent: lord, start: start, end: end, depth: 2))
        }
    }

    /// Sub-periods run in cycle order from the parent's lord, proportional to each lord's years.
    private static func subPeriods(parent: VedicPlanet, start: Int64, end: Int64, depth: Int) -> [Period] {
        guard depth > 0 else { return [] }
        let length = Double(end - start)
        var s = start
        let i0 = indexOf(parent)
        return (0..<9).map { k in
            let lord = ORDER[(i0 + k) % 9].planet
            let e = k == 8 ? end : s + Int64(length * years(lord) / total)
            defer { s = e }
            return Period(lord: lord, startMillis: s, endMillis: e, sub: subPeriods(parent: lord, start: s, end: e, depth: depth - 1))
        }
    }

    static func current(timeline: [Period], at: Int64) -> Current? {
        guard let maha = timeline.first(where: { $0.contains(t: at) }),
              let antar = maha.sub.first(where: { $0.contains(t: at) }),
              let praty = antar.sub.first(where: { $0.contains(t: at) }) else { return nil }
        return Current(maha: maha, antar: antar, pratyantar: praty)
    }

    /// Start of the local day in `zone`.
    static func date(millis: Int64, zone: TimeZone = .current) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.startOfDay(for: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    /// Plain-text block for the AI's system prompt: what's running now plus the full timeline.
    static func describe(timeline: [Period], nowMillis: Int64, zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; f.timeZone = zone
        func d(_ m: Int64) -> String { f.string(from: Date(timeIntervalSince1970: Double(m) / 1000)) }

        var out = "Vimshottari dasha (from the birth Moon's nakshatra; dates are YYYY-MM-DD).\n"
        if let cur = current(timeline: timeline, at: nowMillis) {
            out += "Running now: \(cur.maha.lord) mahadasha (\(d(cur.maha.startMillis)) to \(d(cur.maha.endMillis))), "
            out += "\(cur.antar.lord) antardasha (\(d(cur.antar.startMillis)) to \(d(cur.antar.endMillis))), "
            out += "\(cur.pratyantar.lord) pratyantardasha (\(d(cur.pratyantar.startMillis)) to \(d(cur.pratyantar.endMillis))).\n"
            let ai = cur.maha.sub.firstIndex(of: cur.antar)!
            let mi = timeline.firstIndex(of: cur.maha)!
            let next = ai + 1 < cur.maha.sub.count ? cur.maha.sub[ai + 1]
                : (mi + 1 < timeline.count ? timeline[mi + 1].sub.first : nil)
            if let next { out += "Next antardasha: \(next.lord), from \(d(next.startMillis)).\n" }
            out += "Pratyantardashas within the current antardasha: "
            out += cur.antar.sub.map { "\($0.lord) \(d($0.startMillis))–\(d($0.endMillis))" }.joined(separator: "; ")
            out += ".\n"
        }
        out += "Full timeline (mahadasha: antardashas):\n"
        for m in timeline {
            out += "- \(m.lord) mahadasha \(d(m.startMillis)) to \(d(m.endMillis)): "
            out += m.sub.map { "\($0.lord) \(d($0.startMillis))" }.joined(separator: "; ")
            out += "\n"
        }
        out += "Note: the first mahadasha began before birth; only its remaining balance falls after the birth date."
        return out
    }
}

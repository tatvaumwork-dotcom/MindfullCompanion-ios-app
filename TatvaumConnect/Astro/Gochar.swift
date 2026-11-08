import Foundation

/// Gochar: where the planets are right now (sidereal, Lahiri), and where those transits fall
/// relative to the person's natal ascendant and natal Moon. Used as AI context.
enum Gochar {

    struct Transit: Sendable {
        let position: PlanetPosition
        let houseFromAsc: Int?
        let houseFromMoon: Int?
    }

    /// Current positions; houses are counted whole-sign from the natal ascendant and Moon when known.
    static func transits(nowMillis: Int64, natalAsc: ZodiacSign?, natalMoon: ZodiacSign?) -> [Transit] {
        PlanetPositionCalculator.calculatePlanetPositions(epochMillis: nowMillis).map { p in
            Transit(position: p,
                    houseFromAsc: natalAsc.map { HoroscopeCalculator.wholeSignHouse(planetSign: p.sign, ascSign: $0) },
                    houseFromMoon: natalMoon.map { HoroscopeCalculator.wholeSignHouse(planetSign: p.sign, ascSign: $0) })
        }
    }

    /// Sade Sati phase from the house Saturn transits relative to the natal Moon, or nil if not active.
    static func sadeSati(_ saturnFromMoon: Int?) -> String? {
        switch saturnFromMoon {
        case 12: "rising phase (Saturn in the 12th from the natal Moon)"
        case 1: "peak phase (Saturn over the natal Moon sign)"
        case 2: "setting phase (Saturn in the 2nd from the natal Moon)"
        default: nil
        }
    }

    /// Plain-text block for the AI's system prompt.
    static func describe(nowMillis: Int64, natalAsc: ZodiacSign?, natalMoon: ZodiacSign?, zone: TimeZone = .current) -> String {
        let ts = transits(nowMillis: nowMillis, natalAsc: natalAsc, natalMoon: natalMoon)
        let f = DateFormatter()
        f.dateStyle = .full; f.timeStyle = .short; f.timeZone = zone
        let stamp = f.string(from: Date(timeIntervalSince1970: Double(nowMillis) / 1000))
        let lines = ts.map { t -> String in
            let p = t.position
            let d = Int(p.degreesInSign)
            let m = Int((p.degreesInSign - Double(d)) * 60)
            let retro = p.isRetrograde && p.planet != .Rahu && p.planet != .Ketu ? ", retrograde" : ""
            var houses: [String] = []
            if let h = t.houseFromAsc { houses.append("house \(h) from their ascendant") }
            if let h = t.houseFromMoon { houses.append("house \(h) from their natal Moon") }
            let tail = houses.isEmpty ? "" : " — " + houses.joined(separator: ", ")
            return "- \(p.planet): \(d)°" + String(format: "%02d", m) + "′ \(p.sign), \(CosmicProfile.NAK_NAMES[p.nakshatra.ordinal]) pada \(p.pada)\(retro)\(tail)"
        }
        let saturnFromMoon = ts.first { $0.position.planet == .Saturn }?.houseFromMoon
        let jupiterFromMoon = ts.first { $0.position.planet == .Jupiter }?.houseFromMoon
        var notes: [String] = []
        if natalMoon != nil {
            notes.append(sadeSati(saturnFromMoon).map { "Sade Sati is active: \($0)." } ?? "Sade Sati is not active.")
            if let j = jupiterFromMoon { notes.append("Jupiter is transiting house \(j) from their natal Moon.") }
        }
        var out = "Current planetary positions (gochar), sidereal with Lahiri ayanamsa, computed for \(stamp):\n"
        out += lines.joined(separator: "\n")
        if !notes.isEmpty { out += "\n" + notes.joined(separator: " ") }
        out += "\nThe Moon moves about 13° a day and changes sign every ~2.5 days, so these positions describe today specifically."
        return out
    }
}

import Foundation

/// "As of today": the Vimshottari dasha running right now, down to five levels
/// (Mahadasha → Prana), with plain-language themes.
enum DashaToday {

    struct Level { let name: String, simple: String, span: String }

    static let LEVELS = [
        Level(name: "Mahadasha", simple: "Life chapter", span: "years"),
        Level(name: "Antardasha", simple: "Current phase", span: "months"),
        Level(name: "Pratyantardasha", simple: "This stretch", span: "weeks"),
        Level(name: "Sukshma dasha", simple: "These days", span: "days"),
        Level(name: "Prana dasha", simple: "Right now", span: "hours"),
    ]

    /// Plain meaning, one-word mood, good for, go easy on.
    struct Theme { let meaning: String, mood: String, goodFor: String, goEasy: String }

    static let THEME: [VedicPlanet: Theme] = [
        .Sun: Theme(meaning: "a time to step forward, be seen and take charge of your own life", mood: "confidence", goodFor: "leadership, career visibility, health routines, dealing with authority", goEasy: "ego clashes, pride, burning out"),
        .Moon: Theme(meaning: "a softer, emotional time focused on home, family, comfort and caring for others", mood: "feelings", goodFor: "home, family, nurturing, public connection, rest", goEasy: "mood swings, over-sensitivity, worrying"),
        .Mars: Theme(meaning: "an energetic, driven time for action, courage, competition and getting things done", mood: "drive", goodFor: "bold moves, sport and fitness, property, tackling problems head-on", goEasy: "anger, rushing, accidents, arguments"),
        .Mercury: Theme(meaning: "a busy, curious time for learning, talking, writing, trading and new skills", mood: "ideas", goodFor: "study, communication, business, networking, short trips", goEasy: "overthinking, nervousness, scattered focus"),
        .Jupiter: Theme(meaning: "a time of growth, wisdom, good advice and expanding horizons", mood: "growth", goodFor: "learning, teaching, travel, children, faith, finding good mentors", goEasy: "overdoing it, over-promising, complacency"),
        .Venus: Theme(meaning: "a pleasant time for love, beauty, comfort, creativity and enjoying life", mood: "pleasure", goodFor: "relationships, marriage, art, style, comforts, making peace", goEasy: "over-indulgence, laziness, overspending"),
        .Saturn: Theme(meaning: "a slow, serious time that rewards patience, hard work and responsibility", mood: "discipline", goodFor: "long-term work, structure, duty, building something lasting", goEasy: "delays, heaviness, isolation, impatience with slow results"),
        .Rahu: Theme(meaning: "an ambitious, restless time of big desires, unusual paths and sudden changes", mood: "ambition", goodFor: "bold ambitions, technology, foreign links, breaking out of the box", goEasy: "confusion, obsession, shortcuts, illusions"),
        .Ketu: Theme(meaning: "an inward, detached time for letting go, spirituality and looking within", mood: "letting go", goodFor: "meditation, research, healing, finishing old business", goEasy: "feeling lost, sudden endings, losing motivation"),
    ]

    /// Natural friendships (friends, enemies); Rahu behaves like Saturn, Ketu like Mars.
    private static let FRIENDS: [VedicPlanet: (friends: Set<VedicPlanet>, enemies: Set<VedicPlanet>)] = {
        var base: [VedicPlanet: (friends: Set<VedicPlanet>, enemies: Set<VedicPlanet>)] = [
            .Sun: ([.Moon, .Mars, .Jupiter], [.Venus, .Saturn]),
            .Moon: ([.Sun, .Mercury], []),
            .Mars: ([.Sun, .Moon, .Jupiter], [.Mercury]),
            .Mercury: ([.Sun, .Venus], [.Moon]),
            .Jupiter: ([.Sun, .Moon, .Mars], [.Mercury, .Venus]),
            .Venus: ([.Mercury, .Saturn], [.Sun, .Moon]),
            .Saturn: ([.Mercury, .Venus], [.Sun, .Moon, .Mars]),
        ]
        base[.Rahu] = base[.Saturn]
        base[.Ketu] = base[.Mars]
        return base
    }()

    static func relation(_ a: VedicPlanet, _ b: VedicPlanet) -> String {
        if a == b { return "same" }
        if FRIENDS[a]!.friends.contains(b) { return "friend" }
        if FRIENDS[a]!.enemies.contains(b) { return "enemy" }
        return "neutral"
    }

    static func relationText(_ rel: String) -> String {
        switch rel {
        case "same": "doubles down on the same energy"
        case "friend": "work together smoothly, which makes this a supportive phase"
        case "neutral": "are on neutral terms: results depend on your own effort"
        default: "pull in different directions, which makes this phase mixed. Balance both sides"
        }
    }

    /// One running period plus the periods it sits among (its siblings at that level).
    struct Running: Sendable { let period: Vimshottari.Period, siblings: [Vimshottari.Period] }

    /// The chain of running periods at `now`, Mahadasha first, up to five levels deep.
    static func chain(birthMillis: Int64, moonSiderealLongitude: Double, now: Int64) -> [Running] {
        var list = Vimshottari.timeline(birthMillis: birthMillis, moonSiderealLongitude: moonSiderealLongitude)
        var out: [Running] = []
        for _ in LEVELS {
            guard let cur = list.first(where: { $0.contains(t: now) }) else { break }
            out.append(Running(period: cur, siblings: list))
            list = Vimshottari.subdivide(cur)
        }
        return out
    }

    /// Where a dasha lord sits in the natal chart.
    struct NatalLord {
        let sign: ZodiacSign
        let house: Int
        let rules: [Int]
        let nakshatra: String
        let dignity: String?
        let retrograde: Bool
    }

    static func natalLord(_ lord: VedicPlanet, planets: [PlanetPosition], ascSign: ZodiacSign) -> NatalLord {
        let p = planets.first { $0.planet == lord }!
        let rules = ZodiacSign.allCases.filter { AstrologyData.signLords[$0] == lord }
            .map { HoroscopeCalculator.wholeSignHouse(planetSign: $0, ascSign: ascSign) }.sorted()
        return NatalLord(
            sign: p.sign,
            house: HoroscopeCalculator.wholeSignHouse(planetSign: p.sign, ascSign: ascSign),
            rules: rules,
            nakshatra: CosmicProfile.NAK_NAMES[p.nakshatra.ordinal],
            dignity: CosmicProfile.dignityOf(lord, p.sign.ordinal),
            retrograde: p.isRetrograde && lord != .Rahu && lord != .Ketu)
    }

    static let HOUSE_TITLES = [
        "Self & Identity", "Money & Values", "Mind & Communication", "Home & Roots", "Creativity & Romance", "Work & Health",
        "Partnerships", "Transformation", "Wisdom & Travel", "Career & Legacy", "Community & Dreams", "Spirit & the Unseen",
    ]

    /// "2 yrs 3 mo", "5 months", "12 days", "3 h 20 m", "8 min"
    static func timeLeft(_ ms: Int64) -> String {
        let d = Double(ms) / 86_400_000
        if d >= 365.25 {
            let y = Int(d / 365.25), m = Int((d - Double(y) * 365.25) / 30.44)
            return "\(y) yr\(y > 1 ? "s" : "")\(m > 0 ? " \(m) mo" : "")"
        }
        if d >= 61 { return "\(Int(d / 30.44)) months" }
        if d >= 2 { return "\(Int(d)) days" }
        let h = Double(ms) / 3_600_000
        return h >= 1 ? "\(Int(h)) h \(Int(h.truncatingRemainder(dividingBy: 1) * 60)) m" : "\(max(1, Int(h * 60))) min"
    }

    // MARK: odometer

    struct Orbiter { let name: String, glyph: String, color: UInt32, periodDays: Double; var label = "orbits of the Sun" }

    /// Orbital periods (days) for the "cosmic odometer".
    static let ODOMETER = [
        Orbiter(name: "Sun", glyph: "☉", color: 0xFFFFD36B, periodDays: 365.256363, label: "laps through all 12 signs (Earth’s orbits)"),
        Orbiter(name: "Moon", glyph: "☽", color: 0xFFDFE6F5, periodDays: 27.321661, label: "orbits of Earth"),
        Orbiter(name: "Mercury", glyph: "☿", color: 0xFFB9B2A8, periodDays: 87.969),
        Orbiter(name: "Venus", glyph: "♀", color: 0xFFF3D9A4, periodDays: 224.701),
        Orbiter(name: "Mars", glyph: "♂", color: 0xFFE0623F, periodDays: 686.98),
        Orbiter(name: "Jupiter", glyph: "♃", color: 0xFFD9B48A, periodDays: 4332.59),
        Orbiter(name: "Saturn", glyph: "♄", color: 0xFFE8D39A, periodDays: 10759.22),
        Orbiter(name: "Uranus", glyph: "♅", color: 0xFF9FE3EA, periodDays: 30688.5),
        Orbiter(name: "Neptune", glyph: "♆", color: 0xFF5B7CFF, periodDays: 60182.0),
        Orbiter(name: "Pluto", glyph: "♇", color: 0xFFC7A08A, periodDays: 90560.0),
        Orbiter(name: "Rahu · Ketu", glyph: "☊", color: 0xFFC58CFF, periodDays: 6798.38, label: "backwards laps of the zodiac"),
    ]
}

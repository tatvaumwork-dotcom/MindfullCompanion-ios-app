import Foundation

/// "Your Cosmic Profile": a synthesis of the whole sidereal chart. Text fragments wrapped in
/// **double asterisks** are emphasised in the UI.
struct CosmicProfile: Sendable {
    let summary: String
    let sun: BigThree
    let moon: BigThree
    let rising: BigThree
    let elements: [Bar]
    let modalities: [Bar]
    let purusharthas: [Bar]
    let dominantPurushartha: String
    let purusharthaText: String
    let strengths: [String]
    let growthEdges: [String]
    let northNode: String
    let southNode: String
    let keywords: [(word: String, emphasised: Bool)]

    struct BigThree: Sendable {
        let title: String
        let sign: ZodiacSign
        let element: String
        let subtitle: String
    }

    /// `color` is 0xAARRGGBB.
    struct Bar: Sendable {
        let label: String
        let percent: Int
        let color: Int64
        let top: Bool
    }

    static func build(planets: [PlanetPosition], ascendantLongitude: Double) -> CosmicProfile {
        var pos: [VedicPlanet: PlanetPosition] = [:]
        for p in planets { pos[p.planet] = p }
        func sign(_ p: VedicPlanet) -> Int { pos[p]!.sign.ordinal }
        let sunS = sign(.Sun), moonS = sign(.Moon)
        let ascS = PlanetPositionCalculator.signFromLongitude(ascendantLongitude).0.ordinal
        func t(_ i: Int) -> (first: [String], second: [String]) { SIGN_TRAITS[i] }

        // balances (weighted by planet importance; rising counts as 3)
        var el = Dictionary(uniqueKeysWithValues: ELEMENTS_ORDER.map { ($0, 0.0) })
        var mod = Dictionary(uniqueKeysWithValues: MODS.map { ($0, 0.0) })
        var pur = Dictionary(uniqueKeysWithValues: PADA_NAMES.map { ($0, 0.0) })
        for (p, w) in WEIGHT {
            let si = sign(p)
            el[ELEMENT_OF[si]]! += w
            mod[MODALITY_OF[si]]! += w
            pur[PADA_NAMES[pos[p]!.pada - 1]]! += w
        }
        el[ELEMENT_OF[ascS]]! += 3
        mod[MODALITY_OF[ascS]]! += 3
        func pct(_ m: [String: Double], _ order: [String]) -> [String: Int] {
            let total = order.reduce(0.0) { $0 + m[$1]! }
            return m.mapValues { Int(($0 / total * 100).rounded()) }
        }
        let elP = pct(el, ELEMENTS_ORDER), modP = pct(mod, MODS), purP = pct(pur, PADA_NAMES)
        /// First maximum in declaration order (matches Kotlin maxBy on a linked map).
        func top(_ m: [String: Int], _ order: [String]) -> String {
            var best = order[0]
            for k in order where m[k]! > m[best]! { best = k }
            return best
        }
        let domEl = top(elP, ELEMENTS_ORDER), domMod = top(modP, MODS), domPur = top(purP, PADA_NAMES)
        let lowEl = ELEMENTS_ORDER.filter { elP[$0]! < 10 }

        let moonNak = pos[.Moon]!.nakshatra.ordinal
        let gana = GANA[moonNak]
        let nnS = sign(.Rahu), snS = sign(.Ketu)
        let et = ELEMENT_TEXT[domEl]!

        // summary paragraph
        var sb = "At your core you are **\(t(sunS).first[0])** and **\(t(sunS).first[1])** (Sun in \(SIGNS[sunS])). "
        sb += "Emotionally you are **\(t(moonS).first[moonS == sunS ? 2 : 0])** and **\(t(moonS).first[moonS == sunS ? 3 : 2])** (Moon in \(SIGNS[moonS]))"
        sb += ", and others first meet you as **\(t(ascS).first[1])** and **\(t(ascS).first[3])** (\(SIGNS[ascS]) rising). "
        sb += "With **\(et.name)** as your strongest element you are \(et.strong). "
        sb += "Being mostly \(domMod.lowercased()) makes you \(MODALITY_TEXT[domMod]!.text). "
        sb += "Your Moon in **\(NAK_NAMES[moonNak])** gives you \(GANA_TEXT[gana]!). "
        sb += "Most of your planets sit in **\(domPur)** padas, so you are driven above all by \(PURUSHARTHA_TEXT[domPur]!). "
        sb += "Your soul’s growth lies in developing \(SIGNS[nnS]) qualities (\(t(nnS).first.prefix(2).joined(separator: ", "))) while relying less on familiar \(SIGNS[snS]) patterns."

        // aspects among the seven classical planets, tightest first
        let classical: [VedicPlanet] = [.Sun, .Moon, .Mercury, .Venus, .Mars, .Jupiter, .Saturn]
        struct Found { let a: VedicPlanet, b: VedicPlanet, aspect: String, orb: Double }
        var found: [Found] = []
        for i in classical.indices {
            for j in (i + 1)..<classical.count {
                var diff = abs(pos[classical[i]]!.siderealLongitude - pos[classical[j]]!.siderealLongitude)
                if diff > 180 { diff = 360 - diff }
                if let a = ASPECTS.first(where: { abs(diff - $0.angle) <= $0.orb }) {
                    found.append(Found(a: classical[i], b: classical[j], aspect: a.name, orb: abs(diff - a.angle)))
                }
            }
        }
        found = found.enumerated().sorted { ($0.element.orb, $0.offset) < ($1.element.orb, $1.offset) }.map(\.element)
        func theme(_ p: VedicPlanet) -> String { PLANET_KEYS[p]![0].lowercased() }

        // natural strengths
        var strengths: [String] = []
        strengths.append("**\(t(sunS).first[2].cap()) & \(t(sunS).first[3])**: your \(SIGNS[sunS]) Sun shines through how you act and lead.")
        if moonS != sunS {
            strengths.append("**Emotional \(t(moonS).first[1])**: your \(SIGNS[moonS]) Moon helps you care for yourself and others.")
        }
        for p in classical {
            if let d = dignity(p, sign(p)), d == "Domicile" || d == "Exalted" {
                strengths.append("**Strong \(p.label)** (\(d.lowercased()) in \(SIGNS[sign(p)])): \(PLANET_KEYS[p]!.prefix(3).joined(separator: ", ").lowercased()) come naturally.")
            }
            if sign(p) == navamsaSign(pos[p]!.siderealLongitude) {
                strengths.append("**Vargottama \(p.label)**: \(theme(p)) is consistent and reliable, inside and out.")
            }
        }
        for f in found.filter({ ($0.aspect == "Trine" || $0.aspect == "Sextile") && $0.orb < 4 }).prefix(2) {
            strengths.append("**\(f.a.label) \(f.aspect.lowercased()) \(f.b.label)** \(aspectPhrase(f.aspect, theme(f.a), theme(f.b))).")
        }

        // growth edges
        var edges: [String] = []
        edges.append("**\(t(sunS).second[0].cap()) or \(t(sunS).second[1])** when your \(SIGNS[sunS]) Sun is under stress.")
        if moonS != sunS {
            edges.append("**\(t(moonS).second[0].cap())** moods when emotional needs (\(SIGNS[moonS]) Moon) go unmet.")
        }
        for p in classical {
            if let d = dignity(p, sign(p)), d == "Detriment" || d == "Fall" {
                edges.append("**\(p.label) in \(d.lowercased())** (\(SIGNS[sign(p)])): \(PLANET_KEYS[p]!.prefix(2).joined(separator: " and ").lowercased()) take conscious effort but become a hard-won skill.")
            }
        }
        for f in found.filter({ ($0.aspect == "Square" || $0.aspect == "Opposition") && $0.orb < 4 }).prefix(2) {
            edges.append("**\(f.a.label) \(f.aspect.lowercased()) \(f.b.label)** \(aspectPhrase(f.aspect, theme(f.a), theme(f.b))).")
        }
        for e in lowEl { edges.append("**Low \(ELEMENT_TEXT[e]!.name)**: \(ELEMENT_TEXT[e]!.weak)") }

        // keyword cloud (insertion-ordered, stable sort by weight)
        var order: [String] = [], words: [String: Double] = [:]
        func add(_ w: String, _ n: Double = 1) {
            if words[w] == nil { order.append(w) }
            words[w, default: 0] += n
        }
        t(sunS).first.forEach { add($0, 2) }
        t(moonS).first.prefix(3).forEach { add($0, 1.5) }
        t(ascS).first.prefix(3).forEach { add($0, 1.5) }
        add(t(sign(.Mercury)).first[0]); add(t(sign(.Venus)).first[0]); add(t(sign(.Mars)).first[0])
        let keywords = order.enumerated().sorted { (words[$0.element]!, -$0.offset) > (words[$1.element]!, -$1.offset) }
            .prefix(14).map { (word: $0.element, emphasised: words[$0.element]! >= 2) }

        let rahuNak = NAK_NAMES[pos[.Rahu]!.nakshatra.ordinal]
        let ketuNak = NAK_NAMES[pos[.Ketu]!.nakshatra.ordinal]

        return CosmicProfile(
            summary: sb,
            sun: BigThree(title: "Sun · Self", sign: .of(index: sunS), element: ELEMENT_OF[sunS], subtitle: t(sunS).first[0]),
            moon: BigThree(title: "Moon · Heart", sign: .of(index: moonS), element: ELEMENT_OF[moonS], subtitle: NAK_NAMES[moonNak]),
            rising: BigThree(title: "Rising · Mask", sign: .of(index: ascS), element: ELEMENT_OF[ascS], subtitle: t(ascS).first[1]),
            elements: ELEMENTS_ORDER.map { Bar(label: ELEMENT_TEXT[$0]!.name, percent: elP[$0]!, color: ELEMENT_COLOR[$0]!, top: $0 == domEl) },
            modalities: MODS.map { Bar(label: $0, percent: modP[$0]!, color: MODALITY_TEXT[$0]!.color, top: $0 == domMod) },
            purusharthas: PADA_NAMES.map { Bar(label: $0, percent: purP[$0]!, color: PADA_COLOR[$0]!, top: $0 == domPur) },
            dominantPurushartha: domPur,
            purusharthaText: PURUSHARTHA_TEXT[domPur]!,
            strengths: Array(strengths.prefix(7)),
            growthEdges: Array(edges.prefix(6)),
            northNode: "**North Node in \(SIGNS[nnS])** (\(rahuNak)): grow toward being \(t(nnS).first.prefix(3).joined(separator: ", ")).",
            southNode: "**South Node in \(SIGNS[snS])** (\(ketuNak)): you have innate \(t(snS).first[0]) and \(t(snS).first[1]) gifts, but should guard against being \(t(snS).second[0]).",
            keywords: Array(keywords))
    }

    // MARK: data

    static let SIGNS = ["Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"]
    static let ELEMENT_OF = ["fire", "earth", "air", "water", "fire", "earth", "air", "water", "fire", "earth", "air", "water"]
    private static let MODALITY_OF = ["Cardinal", "Fixed", "Mutable", "Cardinal", "Fixed", "Mutable", "Cardinal", "Fixed", "Mutable", "Cardinal", "Fixed", "Mutable"]
    static let ELEMENT_COLOR: [String: Int64] = ["fire": 0xFFFF7A59, "earth": 0xFF7BD88F, "air": 0xFFF2E27A, "water": 0xFF5FA8FF]
    private static let ELEMENTS_ORDER = ["fire", "earth", "air", "water"]
    private static let MODS = ["Cardinal", "Fixed", "Mutable"]
    private static let PADA_NAMES = ["Dharma", "Artha", "Kama", "Moksha"]
    private static let PADA_COLOR: [String: Int64] = ["Dharma": 0xFFFF7A59, "Artha": 0xFF7BD88F, "Kama": 0xFF5FB3FF, "Moksha": 0xFFC58CFF]

    private static let WEIGHT: [(VedicPlanet, Double)] = [
        (.Sun, 3), (.Moon, 3), (.Mercury, 2), (.Venus, 2), (.Mars, 2), (.Jupiter, 1.5), (.Saturn, 1.5),
    ]

    static let NAK_NAMES = [
        "Ashwini", "Bharani", "Krittika", "Rohini", "Mrigashira", "Ardra", "Punarvasu", "Pushya", "Ashlesha",
        "Magha", "Purva Phalguni", "Uttara Phalguni", "Hasta", "Chitra", "Swati", "Vishakha", "Anuradha", "Jyeshtha",
        "Mula", "Purva Ashadha", "Uttara Ashadha", "Shravana", "Dhanishta", "Shatabhisha", "Purva Bhadrapada", "Uttara Bhadrapada", "Revati",
    ]
    private static let GANA = [
        "Deva", "Manushya", "Rakshasa", "Manushya", "Deva", "Manushya", "Deva", "Deva", "Rakshasa",
        "Rakshasa", "Manushya", "Manushya", "Deva", "Rakshasa", "Deva", "Rakshasa", "Deva", "Rakshasa",
        "Rakshasa", "Manushya", "Manushya", "Deva", "Rakshasa", "Rakshasa", "Manushya", "Manushya", "Deva",
    ]

    /// Navamsa (D9) sign of a sidereal longitude: each 3°20′ pada advances one sign.
    private static func navamsaSign(_ lon: Double) -> Int { (Int(lon / (360.0 / 108)) % 108) % 12 }

    private static let PLANET_KEYS: [VedicPlanet: [String]] = [
        .Sun: ["Identity", "Vitality", "Purpose", "Ego", "Father"],
        .Moon: ["Emotions", "Instinct", "Comfort", "Mother", "Memory"],
        .Mercury: ["Mind", "Communication", "Learning", "Logic", "Siblings"],
        .Venus: ["Love", "Beauty", "Values", "Pleasure", "Money"],
        .Mars: ["Drive", "Courage", "Desire", "Action", "Conflict"],
        .Jupiter: ["Growth", "Luck", "Wisdom", "Faith", "Abundance"],
        .Saturn: ["Discipline", "Structure", "Karma", "Time", "Mastery"],
    ]

    private static let DIGNITY: [VedicPlanet: (domicile: [Int], exalted: Int)] = [
        .Sun: ([4], 0), .Moon: ([3], 1), .Mercury: ([2, 5], 5), .Venus: ([1, 6], 11),
        .Mars: ([0, 7], 9), .Jupiter: ([8, 11], 3), .Saturn: ([9, 10], 6),
    ]
    private static func dignity(_ p: VedicPlanet, _ sign: Int) -> String? {
        guard let d = DIGNITY[p] else { return nil }
        if d.domicile.contains(sign) { return "Domicile" }
        if sign == d.exalted { return "Exalted" }
        if d.domicile.contains(where: { ($0 + 6) % 12 == sign }) { return "Detriment" }
        if (d.exalted + 6) % 12 == sign { return "Fall" }
        return nil
    }

    private static let ASPECTS: [(name: String, angle: Double, orb: Double)] = [
        ("Conjunction", 0, 8), ("Sextile", 60, 5), ("Square", 90, 7), ("Trine", 120, 7), ("Opposition", 180, 8),
    ]
    private static func aspectPhrase(_ name: String, _ a: String, _ b: String) -> String {
        switch name {
        case "Conjunction": "fuses your \(a) with your \(b) into one powerful force"
        case "Trine": "lets your \(a) and \(b) flow together effortlessly, a natural gift"
        case "Sextile": "offers easy opportunities to combine \(a) and \(b)"
        case "Square": "creates productive friction between \(a) and \(b), which drives growth through challenge"
        default: "asks you to balance \(a) against \(b), often mirrored through other people"
        }
    }

    private static let ELEMENT_TEXT: [String: (name: String, strong: String, weak: String)] = [
        "fire": ("Fire", "passionate, spontaneous and inspiring. You lead with enthusiasm and act on instinct", "With little Fire, motivation may need conscious kindling; enthusiasm builds slowly."),
        "earth": ("Earth", "grounded, practical and dependable. You trust what is real, build steadily and finish what you start", "With little Earth, practical routines and finances may need deliberate attention."),
        "air": ("Air", "intellectual, social and communicative. You process life through ideas, conversation and perspective", "With little Air, stepping back to see things objectively may take effort."),
        "water": ("Water", "emotional, intuitive and empathic. You feel your way through life and read people deeply", "With little Water, emotions may be under-expressed and you may need to learn to name your feelings."),
    ]
    private static let MODALITY_TEXT: [String: (color: Int64, text: String)] = [
        "Cardinal": (0xFFFF9F43, "an initiator: you start things, take charge and move toward goals"),
        "Fixed": (0xFFC58CFF, "a sustainer: you are persistent, loyal and determined to see things through"),
        "Mutable": (0xFF6FE0A8, "an adapter: you are flexible, versatile and comfortable with change"),
    ]
    private static let GANA_TEXT = [
        "Deva": "a **Deva** (divine) temperament: gentle, generous, idealistic and drawn to harmony and virtue",
        "Manushya": "a **Manushya** (human) temperament: balanced, ambitious and practical, mixing worldly drive with conscience",
        "Rakshasa": "a **Rakshasa** (fierce) temperament: intense, fearless, independent and protective, with strong will and instincts",
    ]
    private static let PURUSHARTHA_TEXT = [
        "Dharma": "purpose, principle and living by what is right",
        "Artha": "building security, skill and tangible achievement",
        "Kama": "relationships, desire and creative fulfilment",
        "Moksha": "inner freedom, emotional depth and spiritual growth",
    ]

    /// Per sign: (strengths, shadows).
    private static let SIGN_TRAITS: [(first: [String], second: [String])] = [
        (["bold", "energetic", "independent", "courageous"], ["impatient", "impulsive", "quick-tempered"]),
        (["reliable", "patient", "sensual", "grounded"], ["stubborn", "possessive", "resistant to change"]),
        (["witty", "curious", "adaptable", "communicative"], ["restless", "scattered", "inconsistent"]),
        (["caring", "intuitive", "loyal", "protective"], ["moody", "over-sensitive", "clinging to the past"]),
        (["confident", "warm-hearted", "creative", "generous"], ["proud", "attention-seeking", "dramatic"]),
        (["analytical", "helpful", "precise", "practical"], ["over-critical", "anxious", "perfectionist"]),
        (["charming", "fair-minded", "diplomatic", "artistic"], ["indecisive", "people-pleasing", "conflict-avoidant"]),
        (["intense", "perceptive", "loyal", "resilient"], ["secretive", "controlling", "slow to forgive"]),
        (["optimistic", "adventurous", "honest", "philosophical"], ["tactless", "restless", "over-promising"]),
        (["ambitious", "disciplined", "responsible", "strategic"], ["rigid", "pessimistic", "workaholic"]),
        (["original", "humanitarian", "independent", "visionary"], ["detached", "contrarian", "emotionally aloof"]),
        (["compassionate", "imaginative", "intuitive", "gentle"], ["escapist", "easily overwhelmed", "boundary-less"]),
    ]
}

private extension String {
    func cap() -> String { prefix(1).uppercased() + dropFirst() }
}

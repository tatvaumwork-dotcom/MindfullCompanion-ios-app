import Foundation

enum AstrologyData {
    static let signLords: [ZodiacSign: VedicPlanet] = [
        .Aries: .Mars, .Taurus: .Venus, .Gemini: .Mercury, .Cancer: .Moon,
        .Leo: .Sun, .Virgo: .Mercury, .Libra: .Venus, .Scorpio: .Mars,
        .Sagittarius: .Jupiter, .Capricorn: .Saturn, .Aquarius: .Saturn, .Pisces: .Jupiter,
    ]
    static let exaltation: [VedicPlanet: ZodiacSign] = [
        .Sun: .Aries, .Moon: .Taurus, .Mars: .Capricorn, .Mercury: .Virgo,
        .Jupiter: .Cancer, .Venus: .Pisces, .Saturn: .Libra, .Rahu: .Taurus, .Ketu: .Scorpio,
    ]
    static let debilitation: [VedicPlanet: ZodiacSign] = [
        .Sun: .Libra, .Moon: .Scorpio, .Mars: .Cancer, .Mercury: .Pisces,
        .Jupiter: .Capricorn, .Venus: .Virgo, .Saturn: .Aries, .Rahu: .Scorpio, .Ketu: .Taurus,
    ]
    static let naturalBenefics: Set<VedicPlanet> = [.Jupiter, .Venus, .Moon, .Mercury]
    static let naturalMalefics: Set<VedicPlanet> = [.Sun, .Mars, .Saturn, .Rahu, .Ketu]

    static let friends: [VedicPlanet: Set<VedicPlanet>] = [
        .Sun: [.Moon, .Mars, .Jupiter],
        .Moon: [.Sun, .Mercury],
        .Mars: [.Sun, .Moon, .Jupiter],
        .Mercury: [.Sun, .Venus, .Rahu, .Ketu],
        .Jupiter: [.Sun, .Moon, .Mars, .Ketu],
        .Venus: [.Mercury, .Saturn, .Rahu, .Ketu],
        .Saturn: [.Mercury, .Venus],
        .Rahu: [.Mercury, .Venus, .Saturn],
        .Ketu: [.Mars, .Venus, .Saturn],
    ]
    static let neutrals: [VedicPlanet: Set<VedicPlanet>] = [
        .Sun: [.Mercury],
        .Moon: [.Mars, .Jupiter, .Venus, .Saturn],
        .Mars: [.Venus, .Saturn],
        .Mercury: [.Mars, .Jupiter, .Saturn],
        .Jupiter: [.Saturn],
        .Venus: [.Mars, .Jupiter],
        .Saturn: [.Jupiter],
        .Rahu: [.Jupiter],
        .Ketu: [.Mercury, .Jupiter],
    ]
    static let enemies: [VedicPlanet: Set<VedicPlanet>] = [
        .Sun: [.Venus, .Saturn, .Rahu, .Ketu],
        .Moon: [.Rahu, .Ketu],
        .Mars: [.Mercury, .Rahu, .Ketu],
        .Mercury: [.Moon],
        .Jupiter: [.Mercury, .Venus, .Rahu],
        .Venus: [.Sun, .Moon],
        .Saturn: [.Sun, .Moon, .Mars],
        .Rahu: [.Sun, .Moon, .Mars],
        .Ketu: [.Sun, .Moon],
    ]
    static let aspectRules: [VedicPlanet: [Int]] = [
        .Sun: [7], .Moon: [7], .Mars: [4, 7, 8], .Mercury: [7],
        .Jupiter: [5, 7, 9], .Venus: [7], .Saturn: [3, 7, 10],
        .Rahu: [5, 7, 9], .Ketu: [5, 7, 9],
    ]
    static let exaltedInSigns: [ZodiacSign: VedicPlanet] = Dictionary(VedicPlanet.allCases.map { (exaltation[$0]!, $0) }, uniquingKeysWith: { $1 })  // later planet wins (Rahu over Moon), as in Kotlin
}

enum SignRelationship: String, Sendable {
    case OwnSign = "Own Sign", FriendSign = "Friend's Sign", EnemySign = "Enemy's Sign"
    case NeutralSign = "Neutral Sign", Unknown = "Unknown"

    var label: String { rawValue }
}

struct HoroscopePlanet: Sendable {
    let position: PlanetPosition
    let house: Int
    let isExalted: Bool
    let isDebilitated: Bool
    let isOwnSign: Bool
    let isBenefic: Bool
    let isMalefic: Bool
    let signRelationship: SignRelationship
    var neechaBhanga = false
    var neechaBhangaReasons: [String] = []
    var aspectsHouses: [Int] = []
    var aspectedBy: [VedicPlanet] = []
}

struct HouseLord: Sendable {
    let house: Int
    let sign: ZodiacSign
    let lord: VedicPlanet
}

struct HoroscopeChart: Sendable {
    let name: String
    let gender: String
    let birthTime: Int64
    let latitude: Double
    let longitude: Double
    let ascendant: Ascendant
    let ascendantLord: VedicPlanet
    let moonSign: ZodiacSign
    let moonNakshatra: Nakshatra
    let sunSign: ZodiacSign
    let planets: [HoroscopePlanet]
    let houseLords: [HouseLord]
    let planetsInHouses: [Int: [VedicPlanet]]
    let houseAspectedBy: [Int: [VedicPlanet]]
}

enum HoroscopeCalculator {

    static func wholeSignHouse(planetSign: ZodiacSign, ascSign: ZodiacSign) -> Int {
        ((planetSign.ordinal - ascSign.ordinal + 12) % 12) + 1
    }

    static func planetRelationship(planet: VedicPlanet, sign: ZodiacSign) -> SignRelationship {
        guard let lord = AstrologyData.signLords[sign] else { return .Unknown }
        if lord == planet { return .OwnSign }
        if AstrologyData.friends[lord]?.contains(planet) == true { return .FriendSign }
        if AstrologyData.enemies[lord]?.contains(planet) == true { return .EnemySign }
        if AstrologyData.neutrals[lord]?.contains(planet) == true { return .NeutralSign }
        return .Unknown
    }

    static func checkNeechaBhanga(planet: VedicPlanet, planetSign: ZodiacSign, planetHouse: Int,
                                  allPlanets: [HoroscopePlanet]) -> [String] {
        guard AstrologyData.debilitation[planet] == planetSign else { return [] }
        var reasons: [String] = []

        func houseOf(_ p: VedicPlanet) -> Int? { allPlanets.first { $0.position.planet == p }?.house }
        func signOf(_ p: VedicPlanet) -> ZodiacSign? { allPlanets.first { $0.position.planet == p }?.position.sign }
        let moonHouse = houseOf(.Moon)
        func kendraFromLagna(_ h: Int) -> Bool { [1, 4, 7, 10].contains(h) }
        func kendraFromMoon(_ h: Int) -> Bool {
            guard let moonHouse else { return false }
            return [0, 3, 6, 9].contains((h - moonHouse + 12) % 12)
        }

        let debSignLord = AstrologyData.signLords[planetSign]
        let exaltSign = AstrologyData.exaltation[planet]
        let exaltSignLord = exaltSign.flatMap { AstrologyData.signLords[$0] }
        let exaltedInDebSign = AstrologyData.exaltedInSigns[planetSign]

        // Rule 1: lord of debilitation sign in kendra from Lagna or Moon
        if let debSignLord, let h = houseOf(debSignLord) {
            if kendraFromLagna(h) { reasons.append("\(debSignLord) (lord of \(planetSign)) in kendra H\(h) from Lagna") }
            if kendraFromMoon(h) { reasons.append("\(debSignLord) (lord of \(planetSign)) in kendra H\(h) from Moon") }
        }
        // Rule 2: lord of exaltation sign in kendra from Lagna or Moon
        if let exaltSignLord, let exaltSign, let h = houseOf(exaltSignLord) {
            if kendraFromLagna(h) { reasons.append("\(exaltSignLord) (lord of \(exaltSign)) in kendra H\(h) from Lagna") }
            if kendraFromMoon(h) { reasons.append("\(exaltSignLord) (lord of \(exaltSign)) in kendra H\(h) from Moon") }
        }
        // Rule 3: debilitated planet itself in kendra
        if kendraFromLagna(planetHouse) { reasons.append("\(planet) itself in kendra H\(planetHouse) from Lagna") }
        if kendraFromMoon(planetHouse) { reasons.append("\(planet) itself in kendra H\(planetHouse) from Moon") }
        // Rule 4: conjunct with sign lord
        if let debSignLord, signOf(debSignLord) == planetSign {
            reasons.append("Conjunct with \(debSignLord) (lord of \(planetSign))")
        }
        // Rule 5: conjunct with an exalted planet
        for p in allPlanets where p.position.planet != planet && p.position.sign == planetSign
            && AstrologyData.exaltation[p.position.planet] == p.position.sign {
            reasons.append("Conjunct with exalted \(p.position.planet)")
        }
        // Rule 6: lord of debilitation sign is exalted
        if let debSignLord, let s = signOf(debSignLord), AstrologyData.exaltation[debSignLord] == s {
            reasons.append("\(debSignLord) (lord of \(planetSign)) is exalted in \(s)")
        }
        // Rule 7: planet exalted in the debilitation sign is in kendra
        if let ex = exaltedInDebSign, ex != planet, let h = houseOf(ex) {
            if kendraFromLagna(h) { reasons.append("\(ex) (exalted in \(planetSign)) in kendra H\(h) from Lagna") }
            if kendraFromMoon(h) { reasons.append("\(ex) (exalted in \(planetSign)) in kendra H\(h) from Moon") }
        }
        return reasons
    }

    static func generate(name: String, gender: String, birthMillis: Int64, latitude: Double, longitude: Double) -> HoroscopeChart {
        let positions = PlanetPositionCalculator.calculatePlanetPositions(epochMillis: birthMillis)
        let ascendant = PlanetPositionCalculator.calculateAscendant(epochMillis: birthMillis, latitude: latitude, longitude: longitude)
        let ascSign = ascendant.sign

        var planetsInHouses: [Int: [VedicPlanet]] = [:]
        var planets = positions.map { pos -> HoroscopePlanet in
            let house = wholeSignHouse(planetSign: pos.sign, ascSign: ascSign)
            planetsInHouses[house, default: []].append(pos.planet)
            return HoroscopePlanet(
                position: pos, house: house,
                isExalted: AstrologyData.exaltation[pos.planet] == pos.sign,
                isDebilitated: AstrologyData.debilitation[pos.planet] == pos.sign,
                isOwnSign: AstrologyData.signLords[pos.sign] == pos.planet,
                isBenefic: AstrologyData.naturalBenefics.contains(pos.planet),
                isMalefic: AstrologyData.naturalMalefics.contains(pos.planet),
                signRelationship: planetRelationship(planet: pos.planet, sign: pos.sign))
        }

        let base = planets
        planets = base.map { p in
            guard p.isDebilitated else { return p }
            var q = p
            q.neechaBhangaReasons = checkNeechaBhanga(planet: p.position.planet, planetSign: p.position.sign,
                                                      planetHouse: p.house, allPlanets: base)
            q.neechaBhanga = !q.neechaBhangaReasons.isEmpty
            return q
        }

        // Aspects (Graha Drishti), houses counted inclusively
        var planetAspects: [VedicPlanet: [Int]] = [:]
        for p in planets {
            let offsets = AstrologyData.aspectRules[p.position.planet] ?? [7]
            planetAspects[p.position.planet] = offsets.map { ((p.house - 1 + ($0 - 1)) % 12) + 1 }
        }
        var houseAspectedBy: [Int: [VedicPlanet]] = [:]
        for h in 1...12 {
            houseAspectedBy[h] = planets.filter { planetAspects[$0.position.planet]!.contains(h) }.map(\.position.planet)
        }
        let aspected = planets
        planets = aspected.map { p in
            var q = p
            q.aspectsHouses = planetAspects[p.position.planet] ?? []
            q.aspectedBy = aspected.filter {
                $0.position.planet != p.position.planet && planetAspects[$0.position.planet]!.contains(p.house)
            }.map(\.position.planet)
            return q
        }

        let houseLords = (0..<12).map { i -> HouseLord in
            let sign = ZodiacSign.of(index: ascSign.ordinal + i)
            return HouseLord(house: i + 1, sign: sign, lord: AstrologyData.signLords[sign]!)
        }
        let moon = planets.first { $0.position.planet == .Moon }!
        let sun = planets.first { $0.position.planet == .Sun }!

        return HoroscopeChart(
            name: name, gender: gender, birthTime: birthMillis, latitude: latitude, longitude: longitude,
            ascendant: ascendant, ascendantLord: AstrologyData.signLords[ascSign]!,
            moonSign: moon.position.sign, moonNakshatra: moon.position.nakshatra, sunSign: sun.position.sign,
            planets: planets, houseLords: houseLords, planetsInHouses: planetsInHouses, houseAspectedBy: houseAspectedBy)
    }

    static func textReport(_ chart: HoroscopeChart) -> String {
        var lines: [String] = []
        func w(_ s: String) { lines.append(s) }
        func col(_ s: String, _ width: Int) -> String { s + String(repeating: " ", count: max(0, width - s.count)) }
        func rule(_ c: String, _ n: Int) -> String { String(repeating: c, count: n) }
        let iso = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(chart.birthTime) / 1000))

        w(rule("=", 60)); w("BIRTH CHART / HOROSCOPE"); w(rule("=", 60))
        w("Name   : \(chart.name)")
        w("Gender : \(chart.gender)")
        w("Birth  : \(iso)")
        w("Location: " + String(format: "%.4f, %.4f", chart.latitude, chart.longitude))
        w("")
        w("Ascendant     : \(chart.ascendant.sign)")
        w("Ascendant Lord: \(chart.ascendantLord)")
        w("Moon Sign     : \(chart.moonSign)")
        w("Moon Nakshatra: \(chart.moonNakshatra)")
        w("Sun Sign      : \(chart.sunSign)")
        w("")

        w(rule("-", 75))
        w("\(col("Planet", 10)) \(col("Sign", 14)) \(col("House", 6)) \(col("Relationship", 18)) Status")
        w(rule("-", 75))
        for p in chart.planets {
            var status: [String] = []
            if p.isExalted { status.append("Exalted") }
            if p.isDebilitated { status.append(p.neechaBhanga ? "Debilitated (Neecha Bhanga)" : "Debilitated") }
            if p.isOwnSign { status.append("Own Sign") }
            if p.position.isRetrograde { status.append("Retrograde") }
            let s = status.isEmpty ? "-" : status.joined(separator: ", ")
            w("\(col(p.position.planet.label, 10)) \(col(p.position.sign.label, 14)) \(col("\(p.house)", 6)) \(col(p.signRelationship.label, 18)) \(s)")
        }

        let nb = chart.planets.filter(\.neechaBhanga)
        if !nb.isEmpty {
            w(""); w(rule("-", 65)); w("NEECHA BHANGA (Debilitation Cancellation)"); w(rule("-", 65))
            for p in nb {
                w("\(p.position.planet) in \(p.position.sign) — Debilitation cancelled:")
                p.neechaBhangaReasons.forEach { w("  • \($0)") }
            }
        }

        func list(_ a: [VedicPlanet]?) -> String { a.map { $0.map(\.label).joined(separator: ", ") } ?? "-" }

        w(""); w(rule("-", 65)); w("HOUSE TABLE")
        w("\(col("House", 8)) \(col("Sign", 16)) \(col("Lord", 12)) Planets")
        w(rule("-", 65))
        for hl in chart.houseLords {
            w("\(col("\(hl.house)", 8)) \(col(hl.sign.label, 16)) \(col(hl.lord.label, 12)) \(list(chart.planetsInHouses[hl.house]))")
        }

        w(""); w(rule("-", 85)); w("PLANETARY ASPECTS (Graha Drishti)")
        w("\(col("Planet", 10)) \(col("House", 8)) \(col("Aspects Houses", 25)) Aspected By")
        w(rule("-", 85))
        for p in chart.planets {
            let aspH = p.aspectsHouses.isEmpty ? "-" : p.aspectsHouses.map(String.init).joined(separator: ", ")
            let aspBy = p.aspectedBy.isEmpty ? "-" : list(p.aspectedBy)
            w("\(col(p.position.planet.label, 10)) \(col("\(p.house)", 8)) \(col(aspH, 25)) \(aspBy)")
        }

        w(""); w(rule("-", 90)); w("HOUSE ASPECTS (Planets aspecting each house)")
        w("\(col("House", 8)) \(col("Sign", 16)) \(col("Occupied By", 25)) Aspected By")
        w(rule("-", 90))
        for hl in chart.houseLords {
            w("\(col("\(hl.house)", 8)) \(col(hl.sign.label, 16)) \(col(list(chart.planetsInHouses[hl.house]), 25)) \(list(chart.houseAspectedBy[hl.house]))")
        }
        return lines.joined(separator: "\n")
    }
}

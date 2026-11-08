import Foundation
import CAstronomy

// Tropical positions come from Astronomy Engine; the Lahiri ayanamsa, mean lunar node
// and ascendant are computed here with the same definitions Swiss Ephemeris uses.

enum ZodiacSign: String, CaseIterable, Sendable {
    case Aries, Taurus, Gemini, Cancer, Leo, Virgo, Libra, Scorpio, Sagittarius, Capricorn, Aquarius, Pisces

    var label: String { rawValue }
    var ordinal: Int { Self.allCases.firstIndex(of: self)! }
    static func of(index: Int) -> ZodiacSign { allCases[((index % 12) + 12) % 12] }
}

enum Nakshatra: String, CaseIterable, Sendable {
    case Ashwini, Bharani, Krittika, Rohini, Mrigashira, Ardra, Punarvasu, Pushya, Ashlesha, Magha
    case PurvaPhalguni, UttaraPhalguni, Hasta, Chitra, Swati, Vishakha, Anuradha, Jyeshtha, Mula
    case Purvashadha, UttaraAshadha, Shravana, Dhanishta, Shatabhisha, PurvaBhadrapada
    case UttaraBhadrapada, Revati

    var label: String { rawValue }
    var ordinal: Int { Self.allCases.firstIndex(of: self)! }
}

enum VedicPlanet: String, CaseIterable, Sendable {
    case Sun, Moon, Mars, Mercury, Jupiter, Venus, Saturn, Rahu, Ketu

    var label: String { rawValue }
    var ordinal: Int { Self.allCases.firstIndex(of: self)! }

    /// Rahu/Ketu are points on the ecliptic, not bodies.
    var body: astro_body_t? {
        switch self {
        case .Sun: BODY_SUN
        case .Moon: BODY_MOON
        case .Mars: BODY_MARS
        case .Mercury: BODY_MERCURY
        case .Jupiter: BODY_JUPITER
        case .Venus: BODY_VENUS
        case .Saturn: BODY_SATURN
        case .Rahu, .Ketu: nil
        }
    }
}

struct PlanetPosition: Sendable {
    let planet: VedicPlanet
    let siderealLongitude: Double
    let sign: ZodiacSign
    let degreesInSign: Double
    let nakshatra: Nakshatra
    let pada: Int
    let isRetrograde: Bool
}

struct Ascendant: Sendable {
    let longitude: Double
    let sign: ZodiacSign
    let degreesInSign: Double
}

/// Astronomy Engine time from epoch milliseconds (UT).
func astroTime(millis: Int64) -> astro_time_t {
    Astronomy_TimeFromDays(Double(millis) / 86_400_000 - 10957.5)
}

private func rad(_ d: Double) -> Double { d * .pi / 180 }
private func deg(_ r: Double) -> Double { r * 180 / .pi }

enum PlanetPositionCalculator {

    static func signFromLongitude(_ longitude: Double) -> (ZodiacSign, Double) {
        let lon = normalize(longitude)
        return (ZodiacSign.of(index: Int(lon / 30)), lon.truncatingRemainder(dividingBy: 30))
    }

    static func nakshatraFromLongitude(_ longitude: Double) -> (Nakshatra, Int, Double) {
        let lon = normalize(longitude)
        let span = 360.0 / 27
        let index = Int(lon / span) % 27
        let inNak = lon.truncatingRemainder(dividingBy: span)
        let pada = Int(inNak / (span / 4)) + 1
        return (Nakshatra.allCases[index], pada, inNak)
    }

    static func calculatePlanetPositions(epochMillis: Int64) -> [PlanetPosition] {
        let time = astroTime(millis: epochMillis)
        let ayanamsa = lahiriAyanamsa(time: time)
        return VedicPlanet.allCases.map { planet in
            let (tropical, retro) = tropicalLongitude(planet: planet, time: time)
            let sid = normalize(tropical - ayanamsa)
            let (sign, d) = signFromLongitude(sid)
            let (nak, pada, _) = nakshatraFromLongitude(sid)
            return PlanetPosition(planet: planet, siderealLongitude: sid, sign: sign, degreesInSign: d,
                                  nakshatra: nak, pada: pada, isRetrograde: retro)
        }
    }

    static func calculateAscendant(epochMillis: Int64, latitude: Double, longitude: Double) -> Ascendant {
        var time = astroTime(millis: epochMillis)
        let ramc = rad(normalize(Astronomy_SiderealTime(&time) * 15 + longitude))
        let eps = rad(meanObliquity(time: time))
        let phi = rad(latitude)
        let asc = deg(atan2(cos(ramc), -(sin(ramc) * cos(eps) + tan(phi) * sin(eps))))
        let sid = normalize(asc - lahiriAyanamsa(time: time))
        let (sign, d) = signFromLongitude(sid)
        return Ascendant(longitude: sid, sign: sign, degreesInSign: d)
    }

    // MARK: internals

    private static func tropicalLongitude(planet: VedicPlanet, time: astro_time_t) -> (Double, Bool) {
        // Mean nodes are always retrograde.
        switch planet {
        case .Rahu: return (meanNode(time: time), true)
        case .Ketu: return (normalize(meanNode(time: time) + 180), true)
        default:
            let body = planet.body!
            let now = eclipticOfDate(body: body, time: time)
            let before = eclipticOfDate(body: body, time: Astronomy_AddDays(time, -0.5))
            let after = eclipticOfDate(body: body, time: Astronomy_AddDays(time, 0.5))
            return (now, signedDelta(from: before, to: after) < 0)
        }
    }

    /// Apparent geocentric longitude on the true ecliptic of date, degrees.
    private static func eclipticOfDate(body: astro_body_t, time: astro_time_t) -> Double {
        var t = time
        let eqj = Astronomy_GeoVector(body, time, ABERRATION)
        let ect = Astronomy_RotateVector(Astronomy_Rotation_EQJ_ECT(&t), eqj)
        return normalize(deg(atan2(ect.y, ect.x)))
    }

    private static func julianCenturiesTT(_ time: astro_time_t) -> Double { time.tt / 36525 }

    /// Meeus, Astronomical Algorithms 47.7: mean ascending node of the Moon.
    private static func meanNode(time: astro_time_t) -> Double {
        let t = julianCenturiesTT(time)
        return normalize(125.0445479 - 1934.1362891 * t + 0.0020754 * t * t + t * t * t / 467441 - t * t * t * t / 60616000)
    }

    private static func meanObliquity(time: astro_time_t) -> Double {
        let t = julianCenturiesTT(time)
        return 23.4392911 - 0.0130042 * t - 1.64e-7 * t * t + 5.036e-7 * t * t * t
    }

    /// Lahiri (Chitrapaksha) ayanamsa as defined by SE_SIDM_LAHIRI: 23.245524743 deg at JD 2435553.5,
    /// advanced by general precession in longitude.
    static func lahiriAyanamsa(time: astro_time_t) -> Double {
        func precessionArcsec(_ t: Double) -> Double { 5029.0966 * t + 1.11113 * t * t - 0.000006 * t * t * t }
        let t0 = (2435553.5 - 2451545.0) / 36525
        return 23.245524743 + (precessionArcsec(julianCenturiesTT(time)) - precessionArcsec(t0)) / 3600
    }

    private static func signedDelta(from: Double, to: Double) -> Double {
        var d = to - from
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    private static func normalize(_ deg: Double) -> Double {
        let r = deg.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}

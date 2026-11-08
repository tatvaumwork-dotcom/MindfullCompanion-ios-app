import Foundation
import CAstronomy

/// A direction in the sky as seen by an observer: azimuth (0 = north, clockwise) and altitude above the horizon, degrees.
struct SkyPoint: Sendable {
    let azimuth: Double
    let altitude: Double
}

struct SkyPlanet: Sendable {
    let position: PlanetPosition
    let point: SkyPoint
}

struct SkyStar: Sendable {
    let name: String
    let magnitude: Double
    let point: SkyPoint
}

/// A catalogue star: brightness (magnitude) and colour (B-V index: blue-white < 0.3 < yellow < 1.0 < orange-red).
struct SkyCatalogStar: Sendable {
    let point: SkyPoint
    let magnitude: Float
    let colorIndex: Float
}

struct SkyConstellation: Sendable {
    let name: String
    let isZodiac: Bool
    let label: SkyPoint
    let lines: [[SkyPoint]]
}

/// Everything visible from the birthplace at the moment of birth.
struct SkyScene: Sendable {
    let planets: [SkyPlanet]
    let stars: [SkyStar]
    /// The zodiac belt (ecliptic), sampled every 2 degrees of sidereal longitude.
    let ecliptic: [(sidereal: Double, point: SkyPoint)]
    let ascendant: SkyPoint
    /// Real stars down to naked-eye brightness (empty without a catalogue).
    var catalogStars: [SkyCatalogStar] = []
    /// Constellation stick figures (empty without a catalogue).
    var constellations: [SkyConstellation] = []
}

/// A 3x3 rotation flattened row-major, applied straight to a horizontal-frame point (no per-star allocation).
private struct Rot {
    var m: [Double]   // 9 values: out_i = sum_j m[j*3+i] * in_j  (Astronomy Engine convention)

    init(_ r: astro_rotation_t) {
        m = [r.rot.0.0, r.rot.0.1, r.rot.0.2, r.rot.1.0, r.rot.1.1, r.rot.1.2, r.rot.2.0, r.rot.2.1, r.rot.2.2]
    }

    /// Horizontal coordinates of vector (x, y, z) after rotation.
    @inline(__always)
    func horizontal(_ x: Double, _ y: Double, _ z: Double) -> SkyPoint {
        let hx = m[0] * x + m[3] * y + m[6] * z
        let hy = m[1] * x + m[4] * y + m[7] * z
        let hz = m[2] * x + m[5] * y + m[8] * z
        let xy = hypot(hx, hy)
        let alt = atan2(hz, xy) * 180 / .pi
        guard xy > 0 else { return SkyPoint(azimuth: 0, altitude: alt) }
        var lon = atan2(hy, hx) * 180 / .pi      // counterclockwise from north
        if lon < 0 { lon += 360 }
        var az = 360 - lon                        // clockwise from north
        if az >= 360 { az -= 360 }
        return SkyPoint(azimuth: az, altitude: alt)
    }
}

/// Converts the birth moment into an observer's sky: where each planet, the zodiac belt and the
/// brightest stars stood above (or below) the horizon at the birthplace.
enum SkyModel {

    static func compute(epochMillis: Int64, latitude: Double, longitude: Double, catalog: SkyCatalog? = nil) -> SkyScene {
        var time = astroTime(millis: epochMillis)
        let eqdToHor = Astronomy_Rotation_EQD_HOR(&time, Astronomy_MakeObserver(latitude, longitude, 0))
        let eqjToHor = Rot(Astronomy_CombineRotation(Astronomy_Rotation_EQJ_EQD(&time), eqdToHor))
        let ectToHor = Rot(Astronomy_CombineRotation(Astronomy_Rotation_ECT_EQD(&time), eqdToHor))
        let ayanamsa = PlanetPositionCalculator.lahiriAyanamsa(time: time)

        /// A point on the ecliptic of date at the given sidereal longitude.
        func eclipticPoint(_ siderealLon: Double) -> SkyPoint {
            let l = (siderealLon + ayanamsa) * .pi / 180
            return ectToHor.horizontal(cos(l), sin(l), 0)
        }

        /// J2000 right ascension / declination (degrees) as seen from the observer.
        func fromJ2000(_ raDeg: Double, _ decDeg: Double) -> SkyPoint {
            let ra = raDeg * .pi / 180, dec = decDeg * .pi / 180
            let c = cos(dec)
            return eqjToHor.horizontal(c * cos(ra), c * sin(ra), sin(dec))
        }

        let planets = PlanetPositionCalculator.calculatePlanetPositions(epochMillis: epochMillis).map { p -> SkyPlanet in
            let point: SkyPoint
            if let body = p.planet.body {
                let v = Astronomy_GeoVector(body, time, ABERRATION)
                point = eqjToHor.horizontal(v.x, v.y, v.z)
            } else {
                point = eclipticPoint(p.siderealLongitude)
            }
            return SkyPlanet(position: p, point: point)
        }

        let ascLon = PlanetPositionCalculator.calculateAscendant(epochMillis: epochMillis, latitude: latitude, longitude: longitude).longitude
        var scene = SkyScene(
            planets: planets,
            stars: BrightStars.list.map { SkyStar(name: $0.name, magnitude: $0.magnitude, point: fromJ2000($0.raHours * 15, $0.decDeg)) },
            ecliptic: stride(from: 0, through: 360, by: 2).map { (Double($0), eclipticPoint(Double($0))) },
            ascendant: eclipticPoint(ascLon)
        )
        if let catalog {
            scene.catalogStars = catalog.stars.map { SkyCatalogStar(point: fromJ2000($0.raDeg, $0.decDeg), magnitude: $0.magnitude, colorIndex: $0.colorIndex) }
            scene.constellations = catalog.constellations.map { c in
                SkyConstellation(name: c.name, isZodiac: c.isZodiac, label: fromJ2000(c.labelRa, c.labelDec),
                                 lines: c.lines.map { $0.map { fromJ2000($0.0, $0.1) } })
            }
        }
        return scene
    }
}

/// The brightest stars (J2000 right ascension in hours, declination in degrees, visual magnitude) for orientation.
enum BrightStars {
    struct Star: Sendable {
        let name: String
        let raHours: Double
        let decDeg: Double
        let magnitude: Double
    }

    private static let table: [(String, Double, Double, Double)] = [
        ("Sirius", 6.7525, -16.716, -1.46), ("Canopus", 6.3992, -52.696, -0.74),
        ("Rigil Kentaurus", 14.6600, -60.834, -0.27), ("Arcturus", 14.2612, 19.182, -0.05),
        ("Vega", 18.6156, 38.784, 0.03), ("Capella", 5.2782, 45.998, 0.08),
        ("Rigel", 5.2423, -8.202, 0.13), ("Procyon", 7.6550, 5.225, 0.34),
        ("Achernar", 1.6286, -57.237, 0.46), ("Betelgeuse", 5.9195, 7.407, 0.50),
        ("Hadar", 14.0637, -60.373, 0.61), ("Altair", 19.8464, 8.868, 0.76),
        ("Acrux", 12.4433, -63.099, 0.76), ("Aldebaran", 4.5987, 16.509, 0.86),
        ("Antares", 16.4901, -26.432, 0.96), ("Spica", 13.4199, -11.161, 0.97),
        ("Pollux", 7.7553, 28.026, 1.14), ("Fomalhaut", 22.9608, -29.622, 1.16),
        ("Deneb", 20.6905, 45.280, 1.25), ("Mimosa", 12.7954, -59.689, 1.25),
        ("Regulus", 10.1395, 11.967, 1.35), ("Adhara", 6.9771, -28.972, 1.50),
        ("Castor", 7.5767, 31.888, 1.58), ("Shaula", 17.5601, -37.104, 1.62),
        ("Bellatrix", 5.4189, 6.350, 1.64), ("Elnath", 5.4382, 28.608, 1.65),
        ("Alnilam", 5.6036, -1.202, 1.69), ("Alnitak", 5.6793, -1.943, 1.77),
        ("Dubhe", 11.0621, 61.751, 1.79), ("Alkaid", 13.7923, 49.313, 1.86),
        ("Polaris", 2.5303, 89.264, 1.98), ("Mintaka", 5.5334, -0.299, 2.23),
    ]

    static let list: [Star] = table.map { Star(name: $0.0, raHours: $0.1, decDeg: $0.2, magnitude: $0.3) }
}

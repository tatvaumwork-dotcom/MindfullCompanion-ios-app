import XCTest
@testable import TatvaumConnect

private func millis(_ iso: String) -> Int64 {
    Int64(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000)
}

final class EphemerisTests: XCTestCase {
    private let j2000 = millis("2000-01-01T12:00:00Z")
    private func at(_ p: VedicPlanet) -> PlanetPosition {
        PlanetPositionCalculator.calculatePlanetPositions(epochMillis: j2000).first { $0.planet == p }!
    }

    func testSunSiderealAtJ2000() {
        XCTAssertEqual(at(.Sun).siderealLongitude, 256.5, accuracy: 0.1)
        XCTAssertEqual(at(.Sun).sign, .Sagittarius)
    }

    func testMoonAndNodesAtJ2000() {
        XCTAssertEqual(at(.Moon).sign, .Libra)
        XCTAssertEqual(at(.Rahu).siderealLongitude, 101.19, accuracy: 0.05)
        XCTAssertEqual(at(.Ketu).sign, .Capricorn)
    }

    func testRetrogradeFlags() {
        XCTAssertTrue(at(.Saturn).isRetrograde)
        XCTAssertFalse(at(.Sun).isRetrograde)
    }

    func testAscendantRange() {
        let asc = PlanetPositionCalculator.calculateAscendant(epochMillis: j2000, latitude: 0, longitude: 0)
        XCTAssertTrue((0.0...360.0).contains(asc.longitude))
    }

    func testFullChartAndReportGenerate() {
        let chart = HoroscopeCalculator.generate(name: "Test", gender: "Male", birthMillis: millis("1990-05-15T01:00:00Z"),
                                                 latitude: 17.385, longitude: 78.4867)
        XCTAssertEqual(chart.planets.count, 9)
        XCTAssertEqual(chart.houseLords.count, 12)
        XCTAssertEqual(chart.sunSign, .Taurus)
        let sunHouse = chart.planets.first { $0.position.planet == .Sun }!.house
        XCTAssertTrue(sunHouse == 1 || sunHouse == 12, "sun house \(sunHouse)")
        XCTAssertTrue(HoroscopeCalculator.textReport(chart).contains("HOUSE TABLE"))
    }
}

final class SkyModelTests: XCTestCase {
    private let sky = SkyModel.compute(epochMillis: millis("1999-04-15T18:00:00Z"), latitude: 17.385, longitude: 78.4867)

    func testAscendantSitsOnEasternHorizon() {
        XCTAssertEqual(sky.ascendant.altitude, 0, accuracy: 0.5)
        XCTAssertTrue((45.0...135.0).contains(sky.ascendant.azimuth), "azimuth \(sky.ascendant.azimuth)")
    }

    func testSunIsBelowHorizonAtMidnight() {
        let sun = sky.planets.first { $0.position.planet == .Sun }!
        XCTAssertLessThan(sun.point.altitude, -30)
    }

    func testPolarisAltitudeEqualsLatitude() {
        XCTAssertEqual(sky.stars.first { $0.name == "Polaris" }!.point.altitude, 17.385, accuracy: 1)
    }

    func testCatalogLoadsAndProjects() {
        let cat = SkyCatalog.load()
        XCTAssertGreaterThan(cat.stars.count, 4000)
        XCTAssertGreaterThan(cat.constellations.count, 80)
    }
}

final class CosmicProfileTests: XCTestCase {
    private let m = millis("1999-04-15T18:00:00Z")
    private lazy var profile = CosmicProfile.build(
        planets: PlanetPositionCalculator.calculatePlanetPositions(epochMillis: m),
        ascendantLongitude: PlanetPositionCalculator.calculateAscendant(epochMillis: m, latitude: 17.385, longitude: 78.4867).longitude)

    func testBigThreeMatchTheChart() {
        XCTAssertEqual(profile.sun.sign, .Aries)
        XCTAssertEqual(profile.moon.sign, .Pisces)
        XCTAssertEqual(profile.moon.subtitle, "Revati")
        XCTAssertEqual(profile.rising.sign, .Sagittarius)
    }

    func testBalancesAddUpAndHaveOneLeader() {
        for bars in [profile.elements, profile.modalities, profile.purusharthas] {
            XCTAssertTrue((98...102).contains(bars.reduce(0) { $0 + $1.percent }))
            XCTAssertEqual(bars.filter(\.top).count, 1)
        }
    }

    func testSectionsArePopulated() {
        XCTAssertTrue(profile.summary.contains("Sun in Aries"))
        XCTAssertTrue(!profile.strengths.isEmpty && profile.strengths.count <= 7)
        XCTAssertTrue(!profile.growthEdges.isEmpty && profile.growthEdges.count <= 6)
        XCTAssertTrue((5...14).contains(profile.keywords.count))
    }
}

final class GocharTests: XCTestCase {
    private let now = millis("2026-11-07T14:00:00Z")

    func testListsAllNinePlanetsWithHousesFromAscAndMoon() {
        let text = Gochar.describe(nowMillis: now, natalAsc: .Virgo, natalMoon: .Aries, zone: TimeZone(identifier: "Asia/Kolkata")!)
        for p in VedicPlanet.allCases { XCTAssertTrue(text.contains("- \(p.label):"), "missing \(p)") }
        XCTAssertTrue(text.contains("from their ascendant") && text.contains("from their natal Moon"))
        XCTAssertTrue(text.contains("Sade Sati is"))
    }

    func testHousesAreWholeSignFromNatalPoints() {
        for t in Gochar.transits(nowMillis: now, natalAsc: .Virgo, natalMoon: .Aries) {
            XCTAssertEqual(t.houseFromAsc, HoroscopeCalculator.wholeSignHouse(planetSign: t.position.sign, ascSign: .Virgo))
            XCTAssertEqual(t.houseFromMoon, HoroscopeCalculator.wholeSignHouse(planetSign: t.position.sign, ascSign: .Aries))
        }
    }

    func testSadeSatiPhases() {
        XCTAssertTrue(Gochar.sadeSati(12)!.hasPrefix("rising"))
        XCTAssertTrue(Gochar.sadeSati(1)!.hasPrefix("peak"))
        XCTAssertTrue(Gochar.sadeSati(2)!.hasPrefix("setting"))
        XCTAssertNil(Gochar.sadeSati(5))
    }
}

final class VimshottariTests: XCTestCase {
    private let v = Vimshottari.self
    private let birth = millis("1990-01-01T00:00:00Z")
    private let yearMs = 365.25 * 86_400_000

    func testMoonAtStartOfAshwiniGivesFullKetuDasha() {
        let t = v.timeline(birthMillis: birth, moonSiderealLongitude: 0)
        XCTAssertEqual(t[0].lord, .Ketu)
        XCTAssertEqual(t[0].startMillis, birth)
        XCTAssertEqual(Double(t[0].endMillis - t[0].startMillis) / yearMs, 7, accuracy: 1e-6)
        XCTAssertEqual(t.map(\.lord), [.Ketu, .Venus, .Sun, .Moon, .Mars, .Rahu, .Jupiter, .Saturn, .Mercury])
        XCTAssertEqual(Double(t.last!.endMillis - t.first!.startMillis) / yearMs, 120, accuracy: 1e-6)
    }

    func testBalanceIsTheUntraversedPartOfTheNakshatra() {
        let t = v.timeline(birthMillis: birth, moonSiderealLongitude: 20)
        XCTAssertEqual(t[0].lord, .Venus)
        XCTAssertEqual(Double(t[0].endMillis - birth) / yearMs, 10, accuracy: 1e-6)
    }

    func testSubPeriodsStartWithTheirOwnLordAndTileTheParent() {
        let maha = v.timeline(birthMillis: birth, moonSiderealLongitude: 0)[1]
        XCTAssertEqual(maha.sub.first!.lord, .Venus)
        XCTAssertEqual(maha.sub.first!.startMillis, maha.startMillis)
        XCTAssertEqual(maha.sub.last!.endMillis, maha.endMillis)
        XCTAssertEqual(Double(maha.sub.first!.endMillis - maha.sub.first!.startMillis) / yearMs, 20.0 * 20 / 120, accuracy: 1e-6)
        let antar = maha.sub.first!
        XCTAssertEqual(antar.endMillis, antar.sub.last!.endMillis)
    }

    func testCurrentFindsAllThreeLevels() {
        let t = v.timeline(birthMillis: birth, moonSiderealLongitude: 0)
        let c = v.current(timeline: t, at: millis("2026-11-07T00:00:00Z"))!
        XCTAssertEqual(c.maha.lord, .Moon)
        XCTAssertTrue(c.maha.sub.contains(c.antar) && c.antar.sub.contains(c.pratyantar))
    }
}

final class RuleEngineTests: XCTestCase {
    func testPredictProducesOutput() {
        let chart = HoroscopeCalculator.generate(name: "T", gender: "M", birthMillis: millis("1999-04-15T18:00:00Z"),
                                                 latitude: 17.385, longitude: 78.4867)
        let p = RuleEngine().predict(chart)
        XCTAssertFalse(p.traits.isEmpty)
        XCTAssertTrue(p.summary.contains("Sun: House"))
    }
}

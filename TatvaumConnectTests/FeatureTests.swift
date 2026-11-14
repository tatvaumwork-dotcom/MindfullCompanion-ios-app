import XCTest
@testable import TatvaumConnect

final class AstroDataTests: XCTestCase {
    func testEncryptedRulesDecryptToJSON() throws {
        for name in ["house_behaviour", "planet_house_rules"] {
            let data = try XCTUnwrap(AstroData.data(name), name)
            XCTAssertTrue(try JSONSerialization.jsonObject(with: data) is [String: Any], name)
        }
        XCTAssertNil(Bundle.main.url(forResource: "house_behaviour", withExtension: "json"), "plain JSON must not ship")
    }
}

@MainActor
final class ProfileManagerTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func manager() -> ProfileManager { ProfileManager(root: root, llm: LLMService(), ruleEngine: RuleEngine()) }

    func testMigratesSingleProfileIntoMe() throws {
        var p = UserProfile(); p.name = "Asha"; p.isOnboarded = true
        JSONFile<UserProfile>("profile.json", in: root).write(p)
        let m = manager()
        XCTAssertEqual(m.ids.count, 1)
        XCTAssertEqual(m.primaryId, m.active.id)
        XCTAssertEqual(m.active.profileStore.profile.name, "Asha")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "profile.json").path))
    }

    func testAddCancelAndDelete() {
        let m = manager()
        let me = m.active.id
        m.addProfile()
        XCTAssertTrue(m.isAddingActive)
        XCTAssertEqual(m.ids.count, 2)
        m.cancelAdding()
        XCTAssertEqual(m.ids, [me])
        XCTAssertEqual(m.active.id, me)

        m.addProfile(); m.finishAdding()
        let other = m.active.id
        XCTAssertFalse(m.isAddingActive)
        m.delete(me)                         // "Me" can't be deleted
        XCTAssertEqual(m.ids.count, 2)
        m.delete(other)
        XCTAssertEqual(m.ids, [me])
        XCTAssertEqual(m.active.id, me)
    }

    func testCapsAtFive() {
        let m = manager()
        for _ in 0..<10 { m.addProfile(); m.finishAdding() }
        XCTAssertEqual(m.ids.count, ProfileManager.max)
        XCTAssertFalse(m.canAdd)
    }
}

final class DashaTodayTests: XCTestCase {
    func testChainHasFiveNestedLevels() {
        let birth = Int64(Date(timeIntervalSince1970: 924_199_200).timeIntervalSince1970 * 1000)  // 1999-04-15
        let now = nowMillis()
        let chain = DashaToday.chain(birthMillis: birth, moonSiderealLongitude: 123.4, now: now)
        XCTAssertEqual(chain.count, 5)
        for (i, r) in chain.enumerated() {
            XCTAssertTrue(r.period.contains(t: now))
            XCTAssertEqual(r.siblings.count, 9)
            if i > 0 { XCTAssertEqual(r.siblings.first?.lord, chain[i - 1].period.lord) }
        }
    }

    func testTimeLeft() {
        XCTAssertEqual(DashaToday.timeLeft(Int64(400 * 86_400_000)), "1 yr 1 mo")
        XCTAssertEqual(DashaToday.timeLeft(Int64(10 * 86_400_000)), "10 days")
        XCTAssertEqual(DashaToday.timeLeft(Int64(5 * 60_000)), "5 min")
    }
}

final class ShareCardTests: XCTestCase {
    func testRendersPortraitCard() {
        let ms: Int64 = 924_199_200_000
        let planets = PlanetPositionCalculator.calculatePlanetPositions(epochMillis: ms)
        let asc = PlanetPositionCalculator.calculateAscendant(epochMillis: ms, latitude: 17.385, longitude: 78.4867)
        let c = CosmicProfile.build(planets: planets, ascendantLongitude: asc.longitude)
        XCTAssertFalse(c.simple.summary.isEmpty)
        let img = ShareCard.render(c, planets: planets, ascendantLongitude: asc.longitude, birthMillis: ms, place: "Hyderabad")
        XCTAssertEqual(img.size, CGSize(width: 1080, height: 1350))
    }
}

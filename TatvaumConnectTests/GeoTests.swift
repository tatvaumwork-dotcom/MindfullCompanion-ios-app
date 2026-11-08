import XCTest
@testable import TatvaumConnect

final class GeoTests: XCTestCase {
    static let tsv = """
    Paris\tParis\tÎle-de-France\tFrance\t48.85\t2.35\tEurope/Paris\t2138551
    Paris\tParis\tTexas\tUnited States\t33.66\t-95.55\tAmerica/Chicago\t25171
    São Paulo\tSao Paulo\tSão Paulo\tBrazil\t-23.55\t-46.63\tAmerica/Sao_Paulo\t10021295
    Hyderabad\tHyderabad\tTelangana\tIndia\t17.38\t78.48\tAsia/Kolkata\t6809970
    Bad\tline
    """

    func testNormalizeAndParse() {
        XCTAssertEqual(CitySearch.normalize("  São Paulo "), "sao paulo")
        XCTAssertEqual(CitySearch.parse(Self.tsv).count, 4)
    }

    func testSearch() {
        XCTAssertEqual(CitySearch.searchSync(Self.tsv, "hyder").first?.label, "Hyderabad, Telangana, India")
        XCTAssertEqual(CitySearch.searchSync(Self.tsv, "paris").count, 2)
        XCTAssertEqual(CitySearch.searchSync(Self.tsv, "paris, texas").first?.country, "United States")
        XCTAssertEqual(CitySearch.searchSync(Self.tsv, "paris france").first?.region, "Île-de-France")
        XCTAssertEqual(CitySearch.searchSync(Self.tsv, "sao").first?.name, "São Paulo")
        XCTAssertEqual(CitySearch.searchSync(Self.tsv, "aulo").count, 1)   // substring
        XCTAssertTrue(CitySearch.searchSync(Self.tsv, "h").isEmpty)
        XCTAssertEqual(CitySearch.parse("Delhi\tDelhi\tDelhi\tIndia\t1\t2\tz\t5")[0].label, "Delhi, India")
    }

    func testPincodes() {
        let (map, pins) = PincodeGeoService.load("110001\tBaroda House SO\t28.6\t77.2\n110003\tHC SO\t28.7\t77.3\nbad\n560001\tX\t12.9\t77.5")
        XCTAssertEqual(pins, [110001, 110003, 560001])
        XCTAssertEqual(map[110003]?.name, "HC SO")
    }

    @MainActor func testPincodeResolveBundled() async throws {
        let g = PincodeGeoService()
        while !g.isReady { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(g.resolve("110 001")?.name, "Baroda House SO")
        XCTAssertNotNil(g.resolve("110099"))      // nearest
        XCTAssertNil(g.resolve("1234"))
    }

    @MainActor func testBundledCities() async throws {
        let c = CitySearch()
        while !c.isReady { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(c.search("Shanghai").first?.country, "China")
        XCTAssertFalse(c.search("hyderabad, india").isEmpty)
    }
}

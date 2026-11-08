import XCTest
@testable import TatvaumConnect

final class ModelTests: XCTestCase {
    func testTraitInference() {
        XCTAssertEqual(TraitCategory.infer("loves to hike"), .Lifestyle)
        XCTAssertEqual(TraitCategory.infer("bold"), .Personality)
    }
    func testProfileRoundTrip() throws {
        var p = UserProfile(); p.name = "A"; p.isOnboarded = true
        let q = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(q.displayName, "A")
    }
}

import XCTest
@testable import MomRecette

final class MomRecetteTests: XCTestCase {
    func testCategoryDetection() {
        let tarte = Recipe(name: "Tarte aux pommes", category: .desserts)
        XCTAssertEqual(tarte.category, .desserts)
    }
    func testTimeString() {
        XCTAssertEqual(45.timeString, "45 min")
        XCTAssertEqual(90.timeString, "1h30")
    }
}

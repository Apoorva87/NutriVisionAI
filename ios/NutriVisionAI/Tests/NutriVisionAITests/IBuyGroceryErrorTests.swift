import XCTest
@testable import NutriVisionAI

final class IBuyGroceryErrorTests: XCTestCase {
    func testUnauthorizedErrorGivesSettingsRecoveryGuidance() {
        XCTAssertEqual(
            IBuyGroceryError.unauthorized.errorDescription,
            "Store Prices backend rejected the API token. Check Settings → Store Prices."
        )
    }
}

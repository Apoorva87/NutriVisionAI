import XCTest
@testable import NutriVisionAI

final class MealDraftItemTests: XCTestCase {
    func testDraftItemScalesMacrosWithGramMultiplier() {
        var item = MealDraftItem(name: "Oats", baseGrams: 50, caloriesPer100g: 400,
                                 proteinPer100g: 10, carbsPer100g: 60, fatPer100g: 8,
                                 provenance: .search)
        item.gramsMultiplier = 1.5
        XCTAssertEqual(item.grams, 75)
        XCTAssertEqual(item.totalCalories, 300)
        XCTAssertEqual(item.totalProtein, 7.5)
        XCTAssertEqual(item.totalCarbs, 45)
        XCTAssertEqual(item.totalFat, 6)
    }
}

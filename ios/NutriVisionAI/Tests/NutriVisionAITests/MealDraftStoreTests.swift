import XCTest
@testable import NutriVisionAI

final class MealDraftStoreTests: XCTestCase {
    @MainActor
    func testDraftCombinesItemsFromAllLogProvenances() {
        let store = MealDraftStore.shared
        store.clear()
        defer { store.clear() }

        let scanItem = MealDraftItem(
            name: "Scan Apple", baseGrams: 100, caloriesPer100g: 200,
            proteinPer100g: 4, carbsPer100g: 30, fatPer100g: 6, provenance: .scan
        )
        let searchItem = MealDraftItem(
            name: "Search Oats", baseGrams: 100, caloriesPer100g: 200,
            proteinPer100g: 8, carbsPer100g: 40, fatPer100g: 4, provenance: .search
        )
        let aiItem = MealDraftItem(
            name: "AI Curry", baseGrams: 100, caloriesPer100g: 200,
            proteinPer100g: 10, carbsPer100g: 20, fatPer100g: 10, provenance: .ai
        )

        store.addItems([scanItem, searchItem, aiItem])

        XCTAssertEqual(store.itemCount, 3)
        XCTAssertEqual(store.includedItems.map(\.provenance), [.scan, .search, .ai])
        XCTAssertEqual(store.totalCalories, 600)
    }

    @MainActor
    func testBackendMealRequestRetainsAnalysisImagePath() {
        let store = MealDraftStore.shared
        store.clear()
        defer { store.clear() }
        store.mealName = "Lunch"
        store.setBackendImagePath("/uploads/lunch.jpg")
        store.addItem(MealDraftItem(
            name: "Pasta", baseGrams: 100, caloriesPer100g: 150,
            proteinPer100g: 5, carbsPer100g: 30, fatPer100g: 2, provenance: .scan
        ))

        let request = store.makeBackendCreateMealRequest(named: "Lunch")

        XCTAssertEqual(request.mealName, "Lunch")
        XCTAssertEqual(request.imagePath, "/uploads/lunch.jpg")
        XCTAssertEqual(request.items.count, 1)
    }
}

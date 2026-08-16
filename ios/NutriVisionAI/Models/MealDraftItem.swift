import Foundation

// MARK: - Provenance

enum DraftItemProvenance: String {
    case camera
    case barcode
    case database
    case ai
    case custom

    /// Compatibility name for items created by the food search flow.
    static var search: Self { .database }

    var systemImage: String {
        switch self {
        case .camera:   return "camera.fill"
        case .barcode:  return "barcode.viewfinder"
        case .database: return "magnifyingglass"
        case .ai:       return "sparkles"
        case .custom:   return "star.fill"
        }
    }
}

// MARK: - Unified Draft Item

struct MealDraftItem: Identifiable {
    let id: UUID
    let canonicalName: String
    let displayName: String
    let provenance: DraftItemProvenance

    // Base nutrition per 100g (normalized from all sources)
    let baseGrams: Double
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double

    // User adjustments
    var isIncluded: Bool = true
    var gramsMultiplier: Double = 1.0
    var overrideGrams: Double?
    var overrideCalories: Double?
    var overrideProtein: Double?
    var overrideCarbs: Double?
    var overrideFat: Double?

    // Metadata
    var confidence: Double = 1.0
    var dbMatch: Bool = true
    var nutritionAvailable: Bool = true
    var portionLabel: String = "1 serving"

    // Computed
    var grams: Double { overrideGrams ?? (baseGrams * gramsMultiplier) }
    var totalCalories: Double { overrideCalories ?? (grams * caloriesPer100g / 100) }
    var totalProtein: Double { overrideProtein ?? (grams * proteinPer100g / 100) }
    var totalCarbs: Double { overrideCarbs ?? (grams * carbsPer100g / 100) }
    var totalFat: Double { overrideFat ?? (grams * fatPer100g / 100) }

    /// Inert placeholder used as a fallback when a binding's target item was just removed.
    /// Never rendered — exists only to prevent a crash during SwiftUI's animation teardown.
    static let placeholder = MealDraftItem(
        id: UUID(),
        canonicalName: "",
        displayName: "",
        provenance: .custom,
        baseGrams: 0,
        caloriesPer100g: 0,
        proteinPer100g: 0,
        carbsPer100g: 0,
        fatPer100g: 0,
        isIncluded: false
    )
}

// MARK: - Factory Methods

extension MealDraftItem {

    /// Convenience initializer for normalized search results and shared draft tests.
    init(name: String, baseGrams: Double, caloriesPer100g: Double,
         proteinPer100g: Double, carbsPer100g: Double, fatPer100g: Double,
         provenance: DraftItemProvenance) {
        self.init(id: UUID(), canonicalName: name.lowercased(), displayName: name,
                  provenance: provenance, baseGrams: baseGrams,
                  caloriesPer100g: caloriesPer100g, proteinPer100g: proteinPer100g,
                  carbsPer100g: carbsPer100g, fatPer100g: fatPer100g)
    }

    /// From AI vision analysis result (camera flow)
    static func from(analysisItem item: AnalysisItem) -> MealDraftItem {
        let grams = max(item.estimatedGrams, 1)
        return MealDraftItem(
            id: UUID(),
            canonicalName: item.canonicalName,
            displayName: item.detectedName.capitalized,
            provenance: .camera,
            baseGrams: item.estimatedGrams,
            caloriesPer100g: item.calories / grams * 100,
            proteinPer100g: item.proteinG / grams * 100,
            carbsPer100g: item.carbsG / grams * 100,
            fatPer100g: item.fatG / grams * 100,
            confidence: item.confidence,
            dbMatch: item.dbMatch,
            nutritionAvailable: item.nutritionAvailable,
            portionLabel: item.portionLabel
        )
    }

    /// From nutrition DB search result
    static func from(foodItem food: FoodItem) -> MealDraftItem {
        let grams = max(food.servingGrams, 1)
        return MealDraftItem(
            id: UUID(),
            canonicalName: food.canonicalName,
            displayName: food.canonicalName.capitalized,
            provenance: .database,
            baseGrams: food.servingGrams,
            caloriesPer100g: food.calories / grams * 100,
            proteinPer100g: food.proteinG / grams * 100,
            carbsPer100g: food.carbsG / grams * 100,
            fatPer100g: food.fatG / grams * 100
        )
    }

    /// From user's custom food
    static func from(customFood food: CustomFood) -> MealDraftItem {
        let grams = max(food.servingGrams, 1)
        return MealDraftItem(
            id: UUID(),
            canonicalName: food.foodName.lowercased(),
            displayName: food.foodName.capitalized,
            provenance: .custom,
            baseGrams: food.servingGrams,
            caloriesPer100g: food.calories / grams * 100,
            proteinPer100g: food.proteinG / grams * 100,
            carbsPer100g: food.carbsG / grams * 100,
            fatPer100g: food.fatG / grams * 100
        )
    }

    /// From AI food lookup result
    static func from(aiResult result: AIFoodResult) -> MealDraftItem {
        let grams = max(result.servingGrams, 1)
        return MealDraftItem(
            id: UUID(),
            canonicalName: result.foodName.lowercased(),
            displayName: result.foodName.capitalized,
            provenance: .ai,
            baseGrams: result.servingGrams,
            caloriesPer100g: result.calories / grams * 100,
            proteinPer100g: result.proteinG / grams * 100,
            carbsPer100g: result.carbsG / grams * 100,
            fatPer100g: result.fatG / grams * 100,
            confidence: result.confidence ?? 0.7,
            dbMatch: false,
            nutritionAvailable: true
        )
    }

    /// From barcode product lookup (already stores per-100g)
    static func from(barcodeProduct product: OpenFoodFactsProduct, servingGrams: Double) -> MealDraftItem {
        MealDraftItem(
            id: UUID(),
            canonicalName: product.productName.lowercased(),
            displayName: product.productName.capitalized,
            provenance: .barcode,
            baseGrams: servingGrams,
            caloriesPer100g: product.caloriesPer100g,
            proteinPer100g: product.proteinPer100g,
            carbsPer100g: product.carbsPer100g,
            fatPer100g: product.fatPer100g
        )
    }
}

// MARK: - Conversion Methods

extension MealDraftItem {

    /// Convert to AnalysisItem for LocalMealStore.saveMeal() (cloud mode)
    func toAnalysisItem() -> AnalysisItem {
        AnalysisItem(
            detectedName: displayName,
            canonicalName: canonicalName,
            portionLabel: portionLabel,
            estimatedGrams: grams,
            uncertainty: "low",
            confidence: confidence,
            calories: totalCalories,
            proteinG: totalProtein,
            carbsG: totalCarbs,
            fatG: totalFat,
            visionConfidence: confidence,
            dbMatch: dbMatch,
            nutritionAvailable: nutritionAvailable
        )
    }

    /// Convert to MealItemInput for APIClient.createMeal() (backend mode)
    func toMealItemInput() -> MealItemInput {
        MealItemInput(
            detectedName: displayName,
            canonicalName: canonicalName,
            portionLabel: portionLabel,
            estimatedGrams: grams,
            uncertainty: "low",
            confidence: confidence
        )
    }
}

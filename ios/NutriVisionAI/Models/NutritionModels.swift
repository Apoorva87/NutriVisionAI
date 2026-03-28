// Models matching backend schemas.py — the API contract

import Foundation

// MARK: - Auth

struct LoginRequest: Codable {
    let name: String
    let email: String
}

struct LoginResponse: Codable {
    let token: String
    let expiresAt: String
    let user: UserInfo

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case user
    }
}

struct UserInfo: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
    var isSystem: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, email
        case isSystem = "is_system"
    }
}

// MARK: - Nutrition

struct NutritionTotals: Codable {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

// MARK: - Dashboard

struct DashboardResponse: Codable {
    let summary: DashboardSummary
    let recentMeals: [MealRecord]
    let user: UserInfo

    enum CodingKeys: String, CodingKey {
        case summary
        case recentMeals = "recent_meals"
        case user
    }
}

struct DashboardSummary: Codable {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let calorieGoal: Int
    let remainingCalories: Double
    let macroGoals: MacroGoals

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case calorieGoal = "calorie_goal"
        case remainingCalories = "remaining_calories"
        case macroGoals = "macro_goals"
    }
}

struct MacroGoals: Codable {
    let proteinG: Int
    let carbsG: Int
    let fatG: Int

    enum CodingKeys: String, CodingKey {
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

// MARK: - Meals

struct MealRecord: Codable, Identifiable {
    let id: Int
    let mealName: String
    let imagePath: String?
    let createdAt: String
    let totalCalories: Double
    let totalProteinG: Double
    let totalCarbsG: Double
    let totalFatG: Double

    enum CodingKeys: String, CodingKey {
        case id
        case mealName = "meal_name"
        case imagePath = "image_path"
        case createdAt = "created_at"
        case totalCalories = "total_calories"
        case totalProteinG = "total_protein_g"
        case totalCarbsG = "total_carbs_g"
        case totalFatG = "total_fat_g"
    }
}

struct MealItemInput: Codable {
    let detectedName: String
    let canonicalName: String
    let portionLabel: String
    let estimatedGrams: Double
    let uncertainty: String
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case detectedName = "detected_name"
        case canonicalName = "canonical_name"
        case portionLabel = "portion_label"
        case estimatedGrams = "estimated_grams"
        case uncertainty, confidence
    }
}

struct CreateMealRequest: Codable {
    let mealName: String
    let imagePath: String?
    let items: [MealItemInput]

    enum CodingKeys: String, CodingKey {
        case mealName = "meal_name"
        case imagePath = "image_path"
        case items
    }
}

struct CreateMealResponse: Codable {
    let mealId: Int
    let totals: NutritionTotals
    let dashboard: DashboardSummary

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case totals, dashboard
    }
}

// MARK: - Food Search

struct FoodSearchResponse: Codable {
    let items: [FoodItem]
}

struct FoodItem: Codable, Identifiable {
    var id: String { canonicalName }
    let canonicalName: String
    let servingGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let sourceLabel: String?

    init(canonicalName: String, servingGrams: Double, calories: Double,
         proteinG: Double, carbsG: Double, fatG: Double, sourceLabel: String?) {
        self.canonicalName = canonicalName
        self.servingGrams = servingGrams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.sourceLabel = sourceLabel
    }

    enum CodingKeys: String, CodingKey {
        case canonicalName = "canonical_name"
        case servingGrams = "serving_grams"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case sourceLabel = "source_label"
    }
}

// MARK: - Local Nutrition Info (for bundled DB lookups)

struct LocalNutritionInfo {
    let canonicalName: String
    let servingGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let sourceLabel: String
}

// MARK: - Analysis

struct AnalysisItem: Codable, Identifiable {
    var id: String { canonicalName }
    let detectedName: String
    let canonicalName: String
    let portionLabel: String
    let estimatedGrams: Double
    let uncertainty: String
    let confidence: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let visionConfidence: Double
    let dbMatch: Bool
    let nutritionAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case detectedName = "detected_name"
        case canonicalName = "canonical_name"
        case portionLabel = "portion_label"
        case estimatedGrams = "estimated_grams"
        case uncertainty, confidence, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case visionConfidence = "vision_confidence"
        case dbMatch = "db_match"
        case nutritionAvailable = "nutrition_available"
    }
}

struct AnalysisResponse: Codable {
    let imagePath: String?  // Optional for on-device analysis
    let items: [AnalysisItem]
    let totals: NutritionTotals
    let providerMetadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case imagePath = "image_path"
        case items, totals
        case providerMetadata = "provider_metadata"
    }
}

// MARK: - History

struct HistoryResponse: Codable {
    let trends: [[String: AnyCodableValue]]
    let groupedMeals: [String: [MealRecord]]
    let topFoods: [[String: AnyCodableValue]]

    enum CodingKeys: String, CodingKey {
        case trends
        case groupedMeals = "grouped_meals"
        case topFoods = "top_foods"
    }
}

// MARK: - Custom Foods

struct CustomFood: Codable, Identifiable {
    let id: Int
    let foodName: String
    let servingGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case id
        case foodName = "food_name"
        case servingGrams = "serving_grams"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

// MARK: - Settings

struct SettingsResponse: Codable {
    let currentUserName: String?
    let calorieGoal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let modelProvider: String?
    let portionEstimationStyle: String?
    let lmstudioBaseUrl: String?
    let lmstudioVisionModel: String?
    let lmstudioPortionModel: String?

    enum CodingKeys: String, CodingKey {
        case currentUserName = "current_user_name"
        case calorieGoal = "calorie_goal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case modelProvider = "model_provider"
        case portionEstimationStyle = "portion_estimation_style"
        case lmstudioBaseUrl = "lmstudio_base_url"
        case lmstudioVisionModel = "lmstudio_vision_model"
        case lmstudioPortionModel = "lmstudio_portion_model"
    }
}

struct SettingsPayload: Codable {
    var currentUserName: String?
    var calorieGoal: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var modelProvider: String?
    var portionEstimationStyle: String?
    var lmstudioBaseUrl: String?
    var lmstudioVisionModel: String?
    var lmstudioPortionModel: String?

    enum CodingKeys: String, CodingKey {
        case currentUserName = "current_user_name"
        case calorieGoal = "calorie_goal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case modelProvider = "model_provider"
        case portionEstimationStyle = "portion_estimation_style"
        case lmstudioBaseUrl = "lmstudio_base_url"
        case lmstudioVisionModel = "lmstudio_vision_model"
        case lmstudioPortionModel = "lmstudio_portion_model"
    }
}

struct SettingsUpdateResponse: Codable {
    let settings: SettingsResponse
    let dashboard: DashboardSummary
}

// MARK: - AI Food Lookup

struct AIFoodResult: Codable {
    let foodName: String
    let servingGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let confidence: Double?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case servingGrams = "serving_grams"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case confidence
        case notes
    }
}

// MARK: - Generic Error

struct APIError: Codable {
    let error: String
}

// MARK: - Flexible JSON value for dynamic responses

enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - LLM Chat (for meal suggestions)

struct LLMChatRequest: Codable {
    let model: String
    let messages: [LLMMessage]
    let temperature: Double?
}

struct LLMMessage: Codable {
    let role: String
    let content: String
}

struct LLMChatResponse: Codable {
    let choices: [LLMChoice]
}

struct LLMChoice: Codable {
    let message: LLMMessage
}

// MARK: - Meal Suggestion

struct MealSuggestion: Codable, Identifiable {
    var id: String { "\(meal)-\(option)" }
    let meal: String
    let option: Int
    let food: String
    let ingredients: String
    let reason: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case meal, option, food, ingredients, reason, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

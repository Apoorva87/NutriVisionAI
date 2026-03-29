// FoodAnalysisService — Abstraction layer for food image analysis
// Supports: Backend API (default), OpenAI, Google Gemini, and Apple Foundation Models (iOS 26+)

import Foundation
import UIKit

// MARK: - Analysis Provider Protocol

protocol FoodAnalysisProvider {
    func analyzeImage(_ image: UIImage) async throws -> AnalysisResponse
    var providerName: String { get }
    var isAvailable: Bool { get }
}

// MARK: - Analysis Provider Type

enum AnalysisProviderType: String, CaseIterable, Identifiable {
    case backend = "Backend API"
    case openai = "OpenAI"
    case gemini = "Google Gemini"
    case openrouter = "OpenRouter"
    case appleFoundation = "Apple Foundation Models"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .backend: return "Uses your local LM Studio server"
        case .openai: return "Cloud AI via OpenAI (requires API key)"
        case .gemini: return "Cloud AI via Google Gemini (free tier available)"
        case .openrouter: return "Free router + 200+ models (Qwen, Llama, etc.)"
        case .appleFoundation: return "On-device Apple AI (iOS 26+)"
        }
    }

    var systemImage: String {
        switch self {
        case .backend: return "server.rack"
        case .openai: return "brain"
        case .gemini: return "sparkles"
        case .openrouter: return "arrow.triangle.branch"
        case .appleFoundation: return "apple.logo"
        }
    }
}

// MARK: - Food Analysis Service

final class FoodAnalysisService: ObservableObject {
    static let shared = FoodAnalysisService()
    
    @Published var currentProvider: AnalysisProviderType {
        didSet {
            UserDefaults.standard.set(currentProvider.rawValue, forKey: "analysis_provider")
        }
    }
    
    private let backendProvider = BackendAnalysisProvider()
    private let openaiProvider = OpenAIAnalysisProvider()
    private let geminiProvider = GeminiAnalysisProvider()
    private let openrouterProvider = OpenRouterAnalysisProvider()

    #if APPLE_FOUNDATION_MODELS
    private let appleProvider = AppleFoundationAnalysisProvider()
    #endif
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "analysis_provider"),
           let provider = AnalysisProviderType(rawValue: saved) {
            self.currentProvider = provider
        } else {
            self.currentProvider = .backend
        }
    }
    
    var activeProvider: FoodAnalysisProvider {
        switch currentProvider {
        case .backend:
            return backendProvider
        case .openai:
            return openaiProvider
        case .gemini:
            return geminiProvider
        case .openrouter:
            return openrouterProvider
        #if APPLE_FOUNDATION_MODELS
        case .appleFoundation:
            return appleProvider
        #else
        case .appleFoundation:
            // Fallback to backend if Apple Foundation Models not available
            return backendProvider
        #endif
        }
    }

    var isCloudMode: Bool {
        switch currentProvider {
        case .openai, .gemini, .openrouter, .appleFoundation: return true
        case .backend: return false
        }
    }

    var availableProviders: [AnalysisProviderType] {
        var providers: [AnalysisProviderType] = [.backend, .openai, .gemini, .openrouter]

        #if APPLE_FOUNDATION_MODELS
        if appleProvider.isAvailable {
            providers.append(.appleFoundation)
        }
        #endif

        return providers
    }

    func syncFromSettings(_ modelProvider: String) {
        switch modelProvider {
        case "openai": currentProvider = .openai
        case "google": currentProvider = .gemini
        case "openrouter": currentProvider = .openrouter
        case "lmstudio", "ollama": currentProvider = .backend
        default: break
        }
    }

    func analyzeImage(_ image: UIImage) async throws -> AnalysisResponse {
        try await activeProvider.analyzeImage(image)
    }
}

// MARK: - Backend Analysis Provider

final class BackendAnalysisProvider: FoodAnalysisProvider {
    var providerName: String { "Backend API" }
    var isAvailable: Bool { true }
    
    func analyzeImage(_ image: UIImage) async throws -> AnalysisResponse {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw AnalysisError.imageConversionFailed
        }
        return try await APIClient.shared.analyzeImage(data: imageData, filename: "meal.jpg")
    }
}

// MARK: - Apple Foundation Models Provider (iOS 26+)

#if APPLE_FOUNDATION_MODELS
import FoundationModels

@available(iOS 26.0, *)
final class AppleFoundationAnalysisProvider: FoodAnalysisProvider {
    var providerName: String { "Apple Foundation Models" }
    
    var isAvailable: Bool {
        // Check if device supports Foundation Models
        LanguageModel.isAvailable
    }
    
    func analyzeImage(_ image: UIImage) async throws -> AnalysisResponse {
        guard isAvailable else {
            throw AnalysisError.providerUnavailable("Apple Foundation Models requires iOS 26+ and Apple Silicon")
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw AnalysisError.imageConversionFailed
        }
        
        // Create a session with the Foundation Model
        let session = LanguageModelSession()
        
        // Create the prompt for food analysis
        let prompt = """
        Analyze this food image and identify all food items visible. For each item, provide:
        - Food name
        - Estimated portion size in grams
        - Nutritional estimates per portion: calories, protein (g), carbs (g), fat (g)
        - Confidence level (0.0 to 1.0)
        
        Respond in this exact JSON format:
        {
            "items": [
                {
                    "detected_name": "food name",
                    "canonical_name": "standardized food name",
                    "portion_label": "e.g., 1 cup, 2 pieces",
                    "estimated_grams": 150.0,
                    "uncertainty": "low/medium/high",
                    "confidence": 0.85,
                    "calories": 250.0,
                    "protein_g": 10.0,
                    "carbs_g": 30.0,
                    "fat_g": 8.0
                }
            ]
        }
        """
        
        // Create image attachment
        let imageAttachment = ImageResource(data: imageData)
        
        // Send to Foundation Model with image
        let response = try await session.respond(
            to: prompt,
            with: [imageAttachment]
        )
        
        // Parse the response
        let parsedItems = try parseFoundationModelResponse(response.content)
        
        // Calculate totals
        let totals = NutritionTotals(
            calories: parsedItems.reduce(0) { $0 + $1.calories },
            proteinG: parsedItems.reduce(0) { $0 + $1.proteinG },
            carbsG: parsedItems.reduce(0) { $0 + $1.carbsG },
            fatG: parsedItems.reduce(0) { $0 + $1.fatG }
        )
        
        return AnalysisResponse(
            imagePath: nil,
            items: parsedItems,
            totals: totals,
            providerMetadata: ["provider": "apple_foundation_models"]
        )
    }
    
    private func parseFoundationModelResponse(_ content: String) throws -> [AnalysisItem] {
        // Extract JSON from the response
        guard let jsonStart = content.firstIndex(of: "{"),
              let jsonEnd = content.lastIndex(of: "}") else {
            throw AnalysisError.parsingFailed("Could not find JSON in response")
        }
        
        let jsonString = String(content[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AnalysisError.parsingFailed("Could not convert JSON to data")
        }
        
        struct ParsedResponse: Codable {
            let items: [ParsedItem]
        }
        
        struct ParsedItem: Codable {
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
            
            enum CodingKeys: String, CodingKey {
                case detectedName = "detected_name"
                case canonicalName = "canonical_name"
                case portionLabel = "portion_label"
                case estimatedGrams = "estimated_grams"
                case uncertainty, confidence, calories
                case proteinG = "protein_g"
                case carbsG = "carbs_g"
                case fatG = "fat_g"
            }
        }
        
        let decoder = JSONDecoder()
        let parsed = try decoder.decode(ParsedResponse.self, from: jsonData)
        
        return parsed.items.map { item in
            AnalysisItem(
                detectedName: item.detectedName,
                canonicalName: item.canonicalName,
                portionLabel: item.portionLabel,
                estimatedGrams: item.estimatedGrams,
                uncertainty: item.uncertainty,
                confidence: item.confidence,
                calories: item.calories,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG,
                visionConfidence: item.confidence,
                dbMatch: false,
                nutritionAvailable: true
            )
        }
    }
}
#endif

// MARK: - Analysis Errors

enum AnalysisError: LocalizedError {
    case imageConversionFailed
    case providerUnavailable(String)
    case parsingFailed(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to process image"
        case .providerUnavailable(let message):
            return message
        case .parsingFailed(let message):
            return "Failed to parse analysis results: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

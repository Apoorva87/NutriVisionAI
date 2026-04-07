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
            self.currentProvider = .gemini
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

    /// Text-only LLM chat that routes through the active cloud provider or backend.
    func chatCompletion(prompt: String, userMessage: String) async throws -> String {
        if isCloudMode {
            return try await cloudChat(prompt: prompt, userMessage: userMessage)
        } else {
            let messages = [
                LLMMessage(role: "system", content: prompt),
                LLMMessage(role: "user", content: userMessage),
            ]
            let model = UserDefaults.standard.string(forKey: "model_provider") ?? "default"
            return try await APIClient.shared.llmChat(model: model, messages: messages)
        }
    }

    private func cloudChat(prompt: String, userMessage: String) async throws -> String {
        let fullPrompt = "\(prompt)\n\nUser: \(userMessage)"

        switch currentProvider {
        case .gemini:
            return try await geminiTextChat(prompt: fullPrompt)
        case .openai:
            return try await openAITextChat(systemPrompt: prompt, userMessage: userMessage)
        case .openrouter:
            return try await openRouterTextChat(systemPrompt: prompt, userMessage: userMessage)
        default:
            throw AnalysisError.providerUnavailable("Text chat not available for \(currentProvider.rawValue)")
        }
    }

    private func geminiTextChat(prompt: String) async throws -> String {
        guard let apiKey = KeychainHelper.read(key: "google_api_key"), !apiKey.isEmpty else {
            throw AnalysisError.providerUnavailable("Google API key not configured")
        }
        let model = UserDefaults.standard.string(forKey: "google_model") ?? "gemini-2.5-flash"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.7,
                "responseMimeType": "application/json",
                "thinkingConfig": ["thinkingBudget": 0]  // Skip reasoning for speed
            ]
        ] as [String: Any])

        let start = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            NetworkLogger.shared.log(provider: "gemini", action: "text_chat", durationMs: ms, status: "error",
                                      errorMessage: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw AnalysisError.networkError("Gemini HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body.prefix(200))")
        }
        NetworkLogger.shared.log(provider: "gemini", action: "text_chat", durationMs: ms, status: "ok", responseSizeBytes: data.count)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw AnalysisError.parsingFailed("Could not parse Gemini text response")
        }
        return text
    }

    private func openAITextChat(systemPrompt: String, userMessage: String) async throws -> String {
        guard let apiKey = KeychainHelper.read(key: "openai_api_key"), !apiKey.isEmpty else {
            throw AnalysisError.providerUnavailable("OpenAI API key not configured")
        }
        let model = UserDefaults.standard.string(forKey: "openai_model") ?? "gpt-4o-mini"
        let base = UserDefaults.standard.string(forKey: "openai_base_url") ?? "https://api.openai.com/v1"
        let url = URL(string: "\(base)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.7,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ] as [String: Any])

        let openaiStart = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let openaiMs = Int((CFAbsoluteTimeGetCurrent() - openaiStart) * 1000)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            NetworkLogger.shared.log(provider: "openai", action: "text_chat", durationMs: openaiMs, status: "error",
                                      errorMessage: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw AnalysisError.networkError("OpenAI HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body.prefix(200))")
        }
        NetworkLogger.shared.log(provider: "openai", action: "text_chat", durationMs: openaiMs, status: "ok", responseSizeBytes: data.count)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AnalysisError.parsingFailed("Could not parse OpenAI response")
        }
        return content
    }

    private func openRouterTextChat(systemPrompt: String, userMessage: String) async throws -> String {
        guard let apiKey = KeychainHelper.read(key: "openrouter_api_key"), !apiKey.isEmpty else {
            throw AnalysisError.providerUnavailable("OpenRouter API key not configured")
        }
        let model = UserDefaults.standard.string(forKey: "openrouter_model") ?? "openrouter/auto"
        let base = UserDefaults.standard.string(forKey: "openrouter_base_url") ?? "https://openrouter.ai/api/v1"
        let url = URL(string: "\(base)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("NutriVisionAI", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.7,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ] as [String: Any])

        let orStart = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let orMs = Int((CFAbsoluteTimeGetCurrent() - orStart) * 1000)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            NetworkLogger.shared.log(provider: "openrouter", action: "text_chat", durationMs: orMs, status: "error",
                                      errorMessage: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw AnalysisError.networkError("OpenRouter HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body.prefix(200))")
        }
        NetworkLogger.shared.log(provider: "openrouter", action: "text_chat", durationMs: orMs, status: "ok", responseSizeBytes: data.count)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AnalysisError.parsingFailed("Could not parse OpenRouter response")
        }
        return content
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

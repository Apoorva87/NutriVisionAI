// GeminiAnalysisProvider — Calls Google Gemini API directly from iOS.
// Uses bundled NutritionDB for nutrition lookups. Free tier available.

import Foundation
import UIKit

final class GeminiAnalysisProvider: FoodAnalysisProvider {
    var providerName: String { "Google Gemini" }
    var isAvailable: Bool {
        let key = KeychainHelper.read(key: "google_api_key") ?? ""
        return !key.isEmpty
    }

    func analyzeImage(_ image: UIImage) async throws -> AnalysisResponse {
        guard let apiKey = KeychainHelper.read(key: "google_api_key"), !apiKey.isEmpty else {
            throw AnalysisError.providerUnavailable("Google API key not configured. Go to Settings to add it.")
        }
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw AnalysisError.imageConversionFailed
        }

        let model = UserDefaults.standard.string(forKey: "google_model") ?? "gemini-2.0-flash"
        let base64Image = imageData.base64EncodedString()

        let prompt = """
        Analyze this food photo for nutrition logging. For each food item visible:
        1. Identify the food (detected_name: what you see, canonical_name: standard database name)
        2. Estimate portion in grams
        3. Rate your confidence (0.0-1.0)

        For multi-dish plates, identify each component separately (rice, curry, bread, etc).
        Prefer 4-10 items when multiple dishes are visible.
        Use short canonical names that map to a nutrition database.

        Return strict JSON: {"items": [{"detected_name": "...", "canonical_name": "...", "portion_label": "small|medium|large", "estimated_grams": 150.0, "confidence": 0.85}]}
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["inlineData": ["mimeType": "image/jpeg", "data": base64Image]],
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw AnalysisError.networkError("Invalid Gemini URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.networkError("Invalid response")
        }
        if httpResponse.statusCode == 429 {
            throw AnalysisError.providerUnavailable("Gemini rate limit reached. Free tier allows 15 requests per minute. Please wait and try again.")
        }
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
            throw AnalysisError.providerUnavailable("Invalid Google API key. Check Settings.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.networkError("Gemini returned HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let textData = text.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: textData) as? [String: Any],
              let rawItems = parsed["items"] as? [[String: Any]] else {
            throw AnalysisError.parsingFailed("Could not parse Gemini response")
        }

        // Convert to AnalysisItems — same logic as OpenAI provider
        let items: [AnalysisItem] = rawItems.compactMap { raw in
            guard let detected = raw["detected_name"] as? String,
                  let canonical = raw["canonical_name"] as? String else { return nil }

            let grams = (raw["estimated_grams"] as? Double) ?? 150.0
            let confidence = (raw["confidence"] as? Double) ?? 0.7
            let portionLabel = (raw["portion_label"] as? String) ?? "medium"

            let resolved = NutritionDB.shared.resolveAlias(canonical.lowercased())
            let nutrition = NutritionDB.shared.lookup(canonicalName: resolved, grams: grams)

            return AnalysisItem(
                detectedName: detected,
                canonicalName: resolved,
                portionLabel: portionLabel,
                estimatedGrams: grams,
                uncertainty: "AI estimate",
                confidence: confidence,
                calories: nutrition?.calories ?? 0,
                proteinG: nutrition?.proteinG ?? 0,
                carbsG: nutrition?.carbsG ?? 0,
                fatG: nutrition?.fatG ?? 0,
                visionConfidence: confidence,
                dbMatch: nutrition != nil,
                nutritionAvailable: nutrition != nil
            )
        }

        let totals = NutritionTotals(
            calories: items.reduce(0) { $0 + $1.calories },
            proteinG: items.reduce(0) { $0 + $1.proteinG },
            carbsG: items.reduce(0) { $0 + $1.carbsG },
            fatG: items.reduce(0) { $0 + $1.fatG }
        )

        return AnalysisResponse(
            imagePath: nil,
            items: items,
            totals: totals,
            providerMetadata: ["provider": "gemini", "model": model]
        )
    }
}

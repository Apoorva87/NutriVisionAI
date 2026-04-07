// OpenAIAnalysisProvider — Calls OpenAI API directly from iOS.
// Uses bundled NutritionDB for nutrition lookups.

import Foundation
import UIKit

final class OpenAIAnalysisProvider: FoodAnalysisProvider {
    var providerName: String { "OpenAI" }
    var isAvailable: Bool {
        let key = KeychainHelper.read(key: "openai_api_key") ?? ""
        return !key.isEmpty
    }

    func analyzeImage(_ image: UIImage) async throws -> AnalysisResponse {
        guard let apiKey = KeychainHelper.read(key: "openai_api_key"), !apiKey.isEmpty else {
            throw AnalysisError.providerUnavailable("OpenAI API key not configured. Go to Settings to add it.")
        }
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw AnalysisError.imageConversionFailed
        }

        let model = UserDefaults.standard.string(forKey: "openai_model") ?? "gpt-4o-mini"
        let base64Image = imageData.base64EncodedString()

        let prompt = """
        Analyze this food photo for nutrition logging. For each food item visible:
        1. Identify the food (detected_name: what you see, canonical_name: standard database name)
        2. Estimate portion in grams
        3. Estimate nutrition for that portion: calories, protein_g, carbs_g, fat_g
        4. Rate your confidence (0.0-1.0)

        For composite/mixed dishes (biryani, pad thai, chia seed pudding), return ONE item for the whole dish with total nutrition.
        For clearly separate items on a plate (rice + curry + bread), return each component separately.
        Prefer 3-8 items. Use short canonical names that map to a nutrition database.

        Return strict JSON: {"items": [{"detected_name": "...", "canonical_name": "...", "portion_label": "small|medium|large", "estimated_grams": 150.0, "confidence": 0.85, "calories": 250.0, "protein_g": 10.0, "carbs_g": 30.0, "fat_g": 8.0}]}
        """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": [
                            "url": "data:image/jpeg;base64,\(base64Image)"
                        ]]
                    ]
                ]
            ],
            "temperature": 0.2,
            "response_format": ["type": "json_object"]
        ]

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let start = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            NetworkLogger.shared.log(provider: "openai", action: "analyze_image", durationMs: durationMs, status: "error", errorMessage: "Invalid response")
            throw AnalysisError.networkError("Invalid response")
        }
        let httpOk = (200...299).contains(httpResponse.statusCode)
        NetworkLogger.shared.log(provider: "openai", action: "analyze_image", durationMs: durationMs,
                                  status: httpOk ? "ok" : "error",
                                  errorMessage: httpOk ? nil : "HTTP \(httpResponse.statusCode)",
                                  responseSizeBytes: data.count)
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw AnalysisError.providerUnavailable("Invalid OpenAI API key. Check Settings.")
        }
        guard httpOk else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.networkError("OpenAI returned HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse OpenAI response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AnalysisError.parsingFailed("Could not parse OpenAI response structure")
        }

        // Strip markdown fences if present
        var jsonText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```") {
            if let nl = jsonText.firstIndex(of: "\n") { jsonText = String(jsonText[jsonText.index(after: nl)...]) }
            if jsonText.hasSuffix("```") { jsonText = String(jsonText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        guard let contentData = jsonText.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let rawItems = parsed["items"] as? [[String: Any]] else {
            print("OpenAI: failed to parse content as JSON: \(content.prefix(300))")
            throw AnalysisError.parsingFailed("OpenAI response is not valid food JSON")
        }

        // Convert to AnalysisItems with local nutrition lookup
        let items: [AnalysisItem] = rawItems.compactMap { raw in
            guard let detected = raw["detected_name"] as? String,
                  let canonical = raw["canonical_name"] as? String else { return nil }

            let grams = (raw["estimated_grams"] as? Double) ?? 150.0
            let confidence = (raw["confidence"] as? Double) ?? 0.7
            let portionLabel = (raw["portion_label"] as? String) ?? "medium"

            // AI-provided macro estimates (fallback when not in local DB)
            let aiCal = (raw["calories"] as? Double) ?? 0
            let aiPro = (raw["protein_g"] as? Double) ?? 0
            let aiCarb = (raw["carbs_g"] as? Double) ?? 0
            let aiFat = (raw["fat_g"] as? Double) ?? 0

            let resolved = NutritionDB.shared.resolveAlias(canonical.lowercased())
            let nutrition = NutritionDB.shared.lookup(canonicalName: resolved, grams: grams)

            // DB values are authoritative; AI estimates are fallback
            return AnalysisItem(
                detectedName: detected,
                canonicalName: resolved,
                portionLabel: portionLabel,
                estimatedGrams: grams,
                uncertainty: "AI estimate",
                confidence: confidence,
                calories: nutrition?.calories ?? aiCal,
                proteinG: nutrition?.proteinG ?? aiPro,
                carbsG: nutrition?.carbsG ?? aiCarb,
                fatG: nutrition?.fatG ?? aiFat,
                visionConfidence: confidence,
                dbMatch: nutrition != nil,
                nutritionAvailable: (nutrition != nil) || (aiCal > 0)
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
            providerMetadata: ["provider": "openai", "model": model]
        )
    }
}

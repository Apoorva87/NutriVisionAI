// OpenRouterAnalysisProvider — Calls OpenRouter API (OpenAI-compatible) from iOS.
// Supports 200+ models via one API key. Uses bundled NutritionDB for nutrition lookups.

import Foundation
import UIKit

final class OpenRouterAnalysisProvider: FoodAnalysisProvider {
    var providerName: String { "OpenRouter" }
    var isAvailable: Bool {
        let key = KeychainHelper.read(key: "openrouter_api_key") ?? ""
        return !key.isEmpty
    }

    func analyzeImage(_ image: UIImage) async throws -> AnalysisResponse {
        guard let apiKey = KeychainHelper.read(key: "openrouter_api_key"), !apiKey.isEmpty else {
            throw AnalysisError.providerUnavailable("OpenRouter API key not configured. Go to Settings to add it.")
        }

        // Resize to max 1024px to reduce token cost
        let resized = Self.resizeImage(image, maxDimension: 1024)
        guard let imageData = resized.jpegData(compressionQuality: 0.7) else {
            throw AnalysisError.imageConversionFailed
        }

        let model = UserDefaults.standard.string(forKey: "openrouter_model") ?? "openrouter/free"
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
            "temperature": 0.2
        ]

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("NutriVisionAI", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60 // OpenRouter may queue requests

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.networkError("Invalid response")
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw AnalysisError.providerUnavailable("Invalid OpenRouter API key. Check Settings.")
        }
        if httpResponse.statusCode == 429 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.providerUnavailable("OpenRouter rate limit reached. \(body)")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.networkError("OpenRouter returned HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse OpenAI-compatible response
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        print("OpenRouter: raw response (\(data.count) bytes): \(rawBody.prefix(500))")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalysisError.parsingFailed("Could not parse OpenRouter JSON envelope")
        }

        // Check for API-level error
        if let error = json["error"] as? [String: Any] {
            let msg = error["message"] as? String ?? "Unknown error"
            throw AnalysisError.networkError("OpenRouter error: \(msg)")
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("OpenRouter: unexpected structure - keys: \(json.keys)")
            throw AnalysisError.parsingFailed("Could not parse OpenRouter response structure")
        }

        print("OpenRouter: content = \(content.prefix(300))")

        // Extract JSON from content — handle raw JSON, markdown fences, or embedded JSON
        let rawItems = try Self.extractItems(from: content)

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
            providerMetadata: ["provider": "openrouter", "model": model]
        )
    }

    /// Extract items array from various response formats (raw JSON, markdown fences, embedded JSON)
    private static func extractItems(from content: String) throws -> [[String: Any]] {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences: ```json ... ``` or ``` ... ```
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if text.hasSuffix("```") {
                text = String(text.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Try parsing as-is first
        if let data = text.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let items = parsed["items"] as? [[String: Any]] {
            return items
        }

        // Try finding JSON object anywhere in the text (model may include preamble text)
        if let startIdx = text.firstIndex(of: "{"),
           let endIdx = text.lastIndex(of: "}") {
            let jsonSlice = String(text[startIdx...endIdx])
            if let data = jsonSlice.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = parsed["items"] as? [[String: Any]] {
                return items
            }
        }

        print("OpenRouter: failed to extract items from: \(text.prefix(500))")
        throw AnalysisError.parsingFailed("Could not extract food items from OpenRouter response")
    }

    private static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

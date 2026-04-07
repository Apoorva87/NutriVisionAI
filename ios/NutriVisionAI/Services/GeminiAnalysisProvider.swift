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
        let apiKey = KeychainHelper.read(key: "google_api_key")
        print("Gemini: API key present = \(apiKey != nil), length = \(apiKey?.count ?? 0)")
        guard let apiKey, !apiKey.isEmpty else {
            throw AnalysisError.providerUnavailable("Google API key not configured. Go to Settings to add it.")
        }
        // Resize to max 1024px to stay within Gemini's token limits
        let resized = Self.resizeImage(image, maxDimension: 1024)
        guard let imageData = resized.jpegData(compressionQuality: 0.7) else {
            throw AnalysisError.imageConversionFailed
        }
        print("Gemini: sending image \(imageData.count / 1024)KB (\(Int(resized.size.width))x\(Int(resized.size.height)))")

        let model = UserDefaults.standard.string(forKey: "google_model") ?? "gemini-2.5-flash"
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

        print("Gemini: requesting \(model) at \(urlString.prefix(80))...")
        let start = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            NetworkLogger.shared.log(provider: "gemini", action: "analyze_image", durationMs: durationMs, status: "error", errorMessage: "Invalid response")
            throw AnalysisError.networkError("Invalid response")
        }
        let httpOk = (200...299).contains(httpResponse.statusCode)
        NetworkLogger.shared.log(provider: "gemini", action: "analyze_image", durationMs: durationMs,
                                  status: httpOk ? "ok" : "error",
                                  errorMessage: httpOk ? nil : "HTTP \(httpResponse.statusCode)",
                                  responseSizeBytes: data.count)
        print("Gemini: HTTP \(httpResponse.statusCode), response \(data.count) bytes, \(durationMs)ms")
        if httpResponse.statusCode == 429 {
            let errorBody = String(data: data, encoding: .utf8) ?? "no body"
            print("Gemini 429 response: \(errorBody)")
            throw AnalysisError.providerUnavailable("Gemini rate limit reached. Details: \(errorBody)")
        }
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
            let errorBody = String(data: data, encoding: .utf8) ?? "no body"
            print("Gemini \(httpResponse.statusCode) response: \(errorBody)")
            if errorBody.contains("API_KEY_INVALID") || errorBody.contains("PERMISSION_DENIED") {
                throw AnalysisError.providerUnavailable("Invalid Google API key. Check Settings.")
            }
            throw AnalysisError.providerUnavailable("Gemini error (\(httpResponse.statusCode)): \(errorBody.prefix(200))")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.networkError("Gemini returned HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalysisError.parsingFailed("Gemini response is not valid JSON")
        }
        guard let candidates = json["candidates"] as? [[String: Any]], !candidates.isEmpty else {
            // Check for prompt feedback (safety block)
            let feedback = json["promptFeedback"] as? [String: Any]
            let reason = (feedback?["blockReason"] as? String) ?? "unknown"
            throw AnalysisError.parsingFailed("Gemini returned no candidates (reason: \(reason))")
        }
        guard let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]], !parts.isEmpty else {
            let finishReason = candidates.first?["finishReason"] as? String ?? "unknown"
            throw AnalysisError.parsingFailed("Gemini returned empty content (finishReason: \(finishReason))")
        }

        // Skip thinking parts (gemini-2.5-* models return {thought: true, text: "..."} before the real answer)
        let contentParts = parts.filter { ($0["thought"] as? Bool) != true }
        guard let text = contentParts.last?["text"] as? String, !text.isEmpty else {
            throw AnalysisError.parsingFailed("Gemini returned no text content")
        }

        // Strip markdown fences if present (some models wrap JSON in ```json ... ```)
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```") {
            if let nl = jsonText.firstIndex(of: "\n") { jsonText = String(jsonText[jsonText.index(after: nl)...]) }
            if jsonText.hasSuffix("```") { jsonText = String(jsonText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        guard let textData = jsonText.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: textData) as? [String: Any],
              let rawItems = parsed["items"] as? [[String: Any]] else {
            print("Gemini: failed to parse text as JSON: \(text.prefix(300))")
            throw AnalysisError.parsingFailed("Gemini response text is not valid food JSON")
        }

        // Convert to AnalysisItems — same logic as OpenAI provider
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
            providerMetadata: ["provider": "gemini", "model": model]
        )
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

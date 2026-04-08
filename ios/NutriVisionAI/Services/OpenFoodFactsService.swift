// OpenFoodFactsService — Barcode → nutrition lookup via Open Food Facts API.
// Free, no API key required. Rate limit: 100 req/min.

import Foundation

// MARK: - Public Result Model

struct OpenFoodFactsProduct {
    let productName: String
    let brands: String
    let barcode: String
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let servingSizeString: String?
}

// MARK: - Service

final class OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    private let baseURL = "https://world.openfoodfacts.net/api/v2/product"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "NutriVisionAI/1.0 (iOS)"]
        session = URLSession(configuration: config)
    }

    /// Look up a product by barcode. Returns nil if not found (status 0).
    func lookupBarcode(_ barcode: String) async throws -> OpenFoodFactsProduct? {
        let urlString = "\(baseURL)/\(barcode)?fields=product_name,brands,nutriments,serving_size"
        guard let url = URL(string: urlString) else {
            throw OpenFoodFactsError.invalidBarcode
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let start = CFAbsoluteTimeGetCurrent()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            NetworkLogger.shared.log(provider: "openfoodfacts", action: "barcode_lookup",
                                      durationMs: ms, status: "error",
                                      errorMessage: error.localizedDescription)
            throw error
        }
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            NetworkLogger.shared.log(provider: "openfoodfacts", action: "barcode_lookup",
                                      durationMs: ms, status: "error", errorMessage: "Invalid response")
            throw OpenFoodFactsError.networkError("Invalid response")
        }

        guard (200...299).contains(http.statusCode) else {
            NetworkLogger.shared.log(provider: "openfoodfacts", action: "barcode_lookup",
                                      durationMs: ms, status: "error",
                                      errorMessage: "HTTP \(http.statusCode)")
            throw OpenFoodFactsError.networkError("HTTP \(http.statusCode)")
        }

        NetworkLogger.shared.log(provider: "openfoodfacts", action: "barcode_lookup",
                                  durationMs: ms, status: "ok", responseSizeBytes: data.count)

        let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)

        guard decoded.status == 1, let product = decoded.product else {
            return nil // Not found
        }

        let n = product.nutriments
        return OpenFoodFactsProduct(
            productName: product.productName ?? "Unknown Product",
            brands: product.brands ?? "",
            barcode: barcode,
            caloriesPer100g: n?.energyKcal100g ?? 0,
            proteinPer100g: n?.protein100g ?? 0,
            carbsPer100g: n?.carbohydrates100g ?? 0,
            fatPer100g: n?.fat100g ?? 0,
            servingSizeString: product.servingSize
        )
    }
}

// MARK: - Errors

enum OpenFoodFactsError: LocalizedError {
    case invalidBarcode
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBarcode: return "Invalid barcode"
        case .networkError(let msg): return "Open Food Facts: \(msg)"
        }
    }
}

// MARK: - API Response Models (file-internal)

private struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let productName: String?
    let brands: String?
    let nutriments: OFFNutriments?
    let servingSize: String?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case nutriments
        case servingSize = "serving_size"
    }
}

private struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let protein100g: Double?
    let fat100g: Double?
    let carbohydrates100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case protein100g = "proteins_100g"
        case fat100g = "fat_100g"
        case carbohydrates100g = "carbohydrates_100g"
    }
}

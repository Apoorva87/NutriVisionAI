// APIClient — single HTTP client for all backend calls.
// Uses Bearer token auth. Token is stored in Keychain via AuthManager.

import Foundation

final class APIClient {
    static let shared = APIClient()

    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
    private let encoder = JSONEncoder()

    /// Base URL of the backend API (e.g. "http://192.168.1.42:8000")
    /// Set this from Settings or on first launch.
    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "api_base_url") ?? "http://localhost:8000" }
        set { UserDefaults.standard.set(newValue, forKey: "api_base_url") }
    }

    /// Session token for Bearer auth, stored in UserDefaults.
    /// In production, move this to Keychain.
    var token: String? {
        get { UserDefaults.standard.string(forKey: "session_token") }
        set { UserDefaults.standard.set(newValue, forKey: "session_token") }
    }

    private var apiBase: String { "\(baseURL)/api/v1" }

    // MARK: - Auth

    func login(name: String, email: String) async throws -> LoginResponse {
        let body = LoginRequest(name: name, email: email)
        let response: LoginResponse = try await post("/auth/login", body: body)
        token = response.token
        return response
    }

    func logout() async throws {
        let _: [String: Bool] = try await post("/auth/logout", body: EmptyBody())
        token = nil
    }

    func me() async throws -> UserInfo {
        try await get("/auth/me")
    }

    // MARK: - Dashboard

    func dashboard() async throws -> DashboardResponse {
        try await get("/dashboard")
    }

    // MARK: - Meals

    func createMeal(_ request: CreateMealRequest) async throws -> CreateMealResponse {
        try await post("/meals", body: request)
    }

    func getMeal(id: Int) async throws -> [String: AnyCodableValue] {
        try await get("/meals/\(id)")
    }

    func deleteMeal(id: Int) async throws {
        let _: [String: Bool] = try await delete("/meals/\(id)")
    }

    func recentMeals(limit: Int = 10) async throws -> [String: [MealRecord]] {
        try await get("/meals?limit=\(limit)")
    }

    // MARK: - Food Search

    func searchFoods(query: String, limit: Int = 15) async throws -> FoodSearchResponse {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await get("/foods?q=\(encoded)&limit=\(limit)")
    }

    // MARK: - Analysis

    func analyzeImage(data: Data, filename: String) async throws -> AnalysisResponse {
        try await uploadMultipart("/analysis", imageData: data, filename: filename)
    }

    // MARK: - History

    func history(days: Int = 14) async throws -> HistoryResponse {
        try await get("/history?days=\(days)")
    }

    // MARK: - Custom Foods

    func customFoods(limit: Int = 50) async throws -> [String: [CustomFood]] {
        try await get("/custom-foods?limit=\(limit)")
    }

    // MARK: - Settings

    func getSettings() async throws -> SettingsResponse {
        try await get("/settings")
    }

    func updateSettings(_ settings: SettingsPayload) async throws -> SettingsUpdateResponse {
        try await put("/settings", body: settings)
    }

    // MARK: - AI Lookup

    func aiLookup(query: String, webSearch: Bool = false) async throws -> AIFoodResult {
        struct LookupRequest: Codable {
            let query: String
            let webSearch: Bool
            
            enum CodingKeys: String, CodingKey {
                case query
                case webSearch = "web_search"
            }
        }
        
        struct LookupResponse: Codable {
            let query: String
            let aiEstimate: AIFoodResult?
            
            enum CodingKeys: String, CodingKey {
                case query
                case aiEstimate = "ai_estimate"
            }
        }
        
        let request = LookupRequest(query: query, webSearch: webSearch)
        let response: LookupResponse = try await post("/llm/food-lookup", body: request)
        
        guard let result = response.aiEstimate else {
            throw NutriError.api(statusCode: 404, message: "AI could not estimate nutrition for this food")
        }
        
        return result
    }

    // MARK: - HTTP Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(apiBase)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)
        let (data, response) = try await session.data(for: request)
        try checkStatus(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let url = URL(string: "\(apiBase)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        applyAuth(&request)
        let (data, response) = try await session.data(for: request)
        try checkStatus(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(apiBase)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyAuth(&request)
        let (data, response) = try await session.data(for: request)
        try checkStatus(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let url = URL(string: "\(apiBase)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        applyAuth(&request)
        let (data, response) = try await session.data(for: request)
        try checkStatus(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func uploadMultipart<T: Decodable>(_ path: String, imageData: Data, filename: String) async throws -> T {
        let url = URL(string: "\(apiBase)\(path)")!
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try checkStatus(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let apiError = try? decoder.decode(APIError.self, from: data)
            throw NutriError.api(
                statusCode: http.statusCode,
                message: apiError?.error ?? "HTTP \(http.statusCode)"
            )
        }
    }
}

// MARK: - Error

enum NutriError: LocalizedError {
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .api(_, let message): return message
        }
    }
}

// MARK: - Helper

private struct EmptyBody: Encodable {}

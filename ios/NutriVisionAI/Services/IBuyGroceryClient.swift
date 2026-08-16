// IBuyGroceryClient — REST client for the iBuyGrocery backend.
//
// Supports two deployment shapes:
//   • Local dev:   http://localhost:8766            (IBG_DEV_USER_EMAIL set, no key required)
//   • Coolify VPS: https://grocery.apoorvakarnik.top (X-API-Key required)
//
// The base URL is stored in UserDefaults (`ibg_base_url`). The optional API
// key is stored in the Keychain (`ibg_api_token`, name preserved) and, when
// present, is sent as `X-API-Key: sk_search_...` on every request (REST + SSE).
//
// All routes are mounted under `/api/v1/...` per the Coolify deploy spec
// (~/experiments/iBuyGrocery/docs/superpowers/specs/2026-04-18-coolify-deploy-design.md).
// The SSE stream is `/api/v1/events/list/{list_id}`.

import Foundation

enum IBuyGroceryError: LocalizedError {
    case http(Int, String)
    case decoding(String)
    case notConfigured
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "Store Prices service returned HTTP \(code): \(body.prefix(200))"
        case .decoding(let msg):
            return "Could not parse Store Prices response: \(msg)"
        case .notConfigured:
            return "Store Prices backend URL is not set. Open Settings → Store Prices."
        case .unauthorized:
            return "Store Prices backend rejected the API token. Check Settings → Store Prices."
        }
    }
}

final class IBuyGroceryClient {
    static let shared = IBuyGroceryClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys  // we rely on explicit CodingKeys
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    /// Default dev port from iBuyGrocery's `run.sh`.
    static let defaultBaseURL = "http://localhost:8766"

    /// Keychain account name for the VPS API key. Name preserved across the
    /// Bearer→X-API-Key migration so existing devices don't lose their key.
    static let apiTokenKey = "ibg_api_token"

    /// All backend routes are mounted under this prefix. Single source of
    /// truth — never hardcode `/api/v1` anywhere else in this file.
    static let apiPrefix = "/api/v1"

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "ibg_base_url") ?? Self.defaultBaseURL }
        set {
            // Strip trailing slash so `baseURL + "/path"` is always well-formed.
            let trimmed = newValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingSlash()
            UserDefaults.standard.set(trimmed, forKey: "ibg_base_url")
        }
    }

    /// API key read from the Keychain. `nil` or empty means "no auth".
    /// Format on the server is `sk_search_...`; minted at apoorvakarnik.top/account.
    var apiToken: String? {
        let v = KeychainHelper.read(key: Self.apiTokenKey)
        return (v?.isEmpty == false) ? v : nil
    }

    /// Persist (or clear, on empty) the VPS API key in the Keychain.
    func setAPIToken(_ token: String?) {
        let trimmed = (token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? KeychainHelper.delete(key: Self.apiTokenKey)
        } else {
            try? KeychainHelper.save(key: Self.apiTokenKey, value: trimmed)
        }
    }

    /// True when the configured base URL looks like a remote VPS (https:// or
    /// non-localhost host). Used by the UI to decide whether to prompt for a
    /// token and to warn on plain `http://` hosts that aren't localhost.
    var isRemote: Bool {
        guard let url = URL(string: baseURL), let host = url.host else { return false }
        if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") { return false }
        return true
    }

    // MARK: - Lists

    func getTodayList() async throws -> IBGShoppingList {
        try await get("/lists/today")
    }

    func addItems(listId: Int, rawText: String) async throws -> IBGShoppingList {
        struct Body: Encodable { let raw_text: String }
        return try await post("/lists/\(listId)/items", body: Body(raw_text: rawText))
    }

    func clearList(listId: Int) async throws -> IBGShoppingList {
        try await delete("/lists/\(listId)/items")
    }

    func reResolveList(listId: Int, itemIds: [Int]? = nil) async throws {
        struct Body: Encodable { let item_ids: [Int]? }
        let _: EmptyReply = try await post(
            "/lists/\(listId)/re-resolve",
            body: Body(item_ids: itemIds)
        )
    }

    // MARK: - Items

    func reResolveItem(itemId: Int) async throws -> IBGShoppingList {
        try await post("/list-items/\(itemId)/re-resolve", body: EmptyBody())
    }

    func deleteItem(itemId: Int) async throws -> IBGShoppingList {
        try await delete("/list-items/\(itemId)")
    }

    func candidates(itemId: Int) async throws -> [IBGCandidate] {
        try await get("/list-items/\(itemId)/candidates")
    }

    func candidateGroups(itemId: Int) async throws -> [IBGCandidateGroup] {
        try await get("/list-items/\(itemId)/candidate-groups")
    }

    func storeLinks(itemId: Int) async throws -> [IBGCandidate] {
        try await get("/list-items/\(itemId)/store-links")
    }

    func selectCandidate(itemId: Int, candidateItemId: Int) async throws -> IBGShoppingList {
        struct Body: Encodable { let candidate_item_id: Int }
        return try await post("/list-items/\(itemId)/select", body: Body(candidate_item_id: candidateItemId))
    }

    /// action ∈ { "cheaper", "bigger", "not-this-type", "any-store" }
    func quickAction(itemId: Int, action: String) async throws -> IBGShoppingList {
        try await post("/list-items/\(itemId)/actions/\(action)", body: EmptyBody())
    }

    // MARK: - Basket

    func basket(listId: Int, mode: String, storeId: Int? = nil) async throws -> IBGBasketPlan {
        var query = "mode=\(mode)"
        if let storeId = storeId { query += "&store_id=\(storeId)" }
        return try await get("/baskets/\(listId)?\(query)")
    }

    func basketStores(listId: Int) async throws -> [IBGAvailableStore] {
        try await get("/baskets/\(listId)/stores")
    }

    // MARK: - Settings

    func getSettings() async throws -> IBGSettings {
        try await get("/settings")
    }

    func patchSettings(_ patch: IBGSettingsPatch) async throws -> IBGSettings {
        try await patchJSON("/settings", body: patch)
    }

    // MARK: - Providers

    func listProviders() async throws -> [IBGProvider] {
        try await get("/providers")
    }

    func setProviderEnabled(providerId: Int, enabled: Bool) async throws -> IBGProvider {
        struct Body: Encodable { let enabled: Bool }
        return try await patchJSON("/providers/\(providerId)", body: Body(enabled: enabled))
    }

    func providerStoreOptions(providerId: Int) async throws -> [IBGProviderStoreOption] {
        try await get("/providers/\(providerId)/store-options")
    }

    func selectProviderStore(providerId: Int, externalStoreId: String) async throws -> IBGProvider {
        struct Body: Encodable { let external_store_id: String }
        return try await put(
            "/providers/\(providerId)/store-selection",
            body: Body(external_store_id: externalStoreId)
        )
    }

    /// Build the SSE URL for live item-resolved updates on a given list.
    func eventsURL(listId: Int) -> URL? {
        URL(string: "\(baseURL)\(Self.apiPrefix)/events/list/\(listId)")
    }

    // MARK: - Health & Identity

    /// Unauthenticated health probe — Coolify uses this for container health
    /// checks; the iOS Settings UI uses it for "Save & Test" reachability.
    func healthz() async throws -> IBGHealth {
        try await get("/healthz")
    }

    /// Identity of the authenticated caller. Returns 401 if no/invalid key.
    func authMe() async throws -> IBGUserMe {
        try await get("/auth/me")
    }

    /// Quick reachability ping — hits the unauthenticated /healthz endpoint
    /// so it succeeds even before the user has pasted an API key.
    func ping() async -> (ok: Bool, message: String) {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await healthz()
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            return (true, "Reachable (\(ms)ms)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - HTTP helpers

    /// Resolve a backend-relative path into an absolute URL.
    /// Paths beginning with `/api/` (already prefixed) are passed through
    /// unchanged; everything else is implicitly under `/api/v1/...`. This
    /// keeps the rest of the file readable while still letting `healthz` and
    /// `auth/me` use explicit absolute paths if a future migration requires it.
    internal func requestURL(for path: String) throws -> URL {
        let fullPath = path.hasPrefix("/api/") ? path : (Self.apiPrefix + path)
        guard !baseURL.isEmpty, let url = URL(string: baseURL + fullPath) else {
            throw IBuyGroceryError.notConfigured
        }
        return url
    }

    /// Shared header setup: Accept + X-API-Key + Client ID.
    /// Applied to every outbound REST request and to the SSE connect request
    /// via `authHeaders()`. The Coolify backend reads `X-API-Key` (forwarded
    /// to apoorvakarnik.top's auth verifier); `Authorization: Bearer` is no
    /// longer used.
    func authHeaders() -> [String: String] {
        var h: [String: String] = [
            "Accept": "application/json",
            "X-Client": "NutriVisionAI-iOS",
        ]
        if let token = apiToken {
            h["X-API-Key"] = token
        }
        return h
    }

    private func applyAuth(_ req: inout URLRequest) {
        for (k, v) in authHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: try requestURL(for: path))
        req.httpMethod = "GET"
        applyAuth(&req)
        return try await send(req, action: path)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: try requestURL(for: path))
        req.httpMethod = "DELETE"
        applyAuth(&req)
        return try await send(req, action: path)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: try requestURL(for: path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        req.httpBody = try encoder.encode(body)
        return try await send(req, action: path)
    }

    private func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: try requestURL(for: path))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        req.httpBody = try encoder.encode(body)
        return try await send(req, action: path)
    }

    private func patchJSON<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: try requestURL(for: path))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        req.httpBody = try encoder.encode(body)
        return try await send(req, action: path)
    }

    private func send<T: Decodable>(_ request: URLRequest, action: String) async throws -> T {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await session.data(for: request)
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                NetworkLogger.shared.log(provider: "ibuygrocery", action: action,
                                          durationMs: ms, status: "error",
                                          errorMessage: "HTTP \(http.statusCode)")
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw IBuyGroceryError.unauthorized
                }
                throw IBuyGroceryError.http(http.statusCode, body)
            }
            NetworkLogger.shared.log(provider: "ibuygrocery", action: action,
                                      durationMs: ms, status: "ok",
                                      responseSizeBytes: data.count)
            if T.self == EmptyReply.self {
                return EmptyReply() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw IBuyGroceryError.decoding(error.localizedDescription)
            }
        } catch let err as IBuyGroceryError {
            throw err
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            NetworkLogger.shared.log(provider: "ibuygrocery", action: action,
                                      durationMs: ms, status: "error",
                                      errorMessage: error.localizedDescription)
            throw error
        }
    }
}

private struct EmptyBody: Encodable {}
private struct EmptyReply: Decodable {}

private extension String {
    func trimmingSlash() -> String {
        var s = self
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

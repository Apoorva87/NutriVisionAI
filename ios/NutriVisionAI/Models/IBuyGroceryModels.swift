// IBuyGroceryModels — Swift mirrors of the iBuyGrocery FastAPI schemas.
// See: ~/experiments/iBuyGrocery/backend/app/api/schemas.py

import Foundation

// MARK: - Enums (string-backed to match the backend's JSON)

enum IBGItemState: String, Codable {
    case queued
    case searching
    case needsReview = "needs_review"
    case recommended
    case selected
    case purchased
    case stale
    case providerError = "provider_error"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IBGItemState(rawValue: raw) ?? .unknown
    }
}

enum IBGProviderRunState: String, Codable {
    case running, success, empty, timeout, error, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IBGProviderRunState(rawValue: raw) ?? .unknown
    }
}

enum IBGOptimizeMode: String, Codable, CaseIterable, Identifiable {
    case balanced, value
    case preferredStore = "preferred_store"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .value: return "Best Value"
        case .preferredStore: return "Preferred Store"
        }
    }
}

enum IBGLocationMode: String, Codable {
    case storePicker = "store_picker"
    case zipOnly = "zip_only"
    case searchOnly = "search_only"
    case none
}

enum IBGLocationStatus: String, Codable {
    case ready
    case zipRequired = "zip_required"
    case selectionNeeded = "selection_needed"
    case searchOnly = "search_only"
    case zipOptional = "zip_optional"
}

// MARK: - Lists & items

struct IBGCandidate: Codable, Identifiable, Hashable {
    let id: Int
    let rank: Int
    let productTitle: String
    let brand: String?
    let storeName: String
    let price: Double
    let sizeText: String?
    let unitPriceLabel: String?
    let imageUrl: String?
    let productUrl: String?
    let explanationTags: [String]
    let finalScore: Double
    let fetchedAt: String  // ISO-8601

    enum CodingKeys: String, CodingKey {
        case id, rank, brand, price
        case productTitle = "product_title"
        case storeName = "store_name"
        case sizeText = "size_text"
        case unitPriceLabel = "unit_price_label"
        case imageUrl = "image_url"
        case productUrl = "product_url"
        case explanationTags = "explanation_tags"
        case finalScore = "final_score"
        case fetchedAt = "fetched_at"
    }
}

struct IBGCandidateGroup: Codable, Identifiable {
    let id: String
    let title: String
    let brand: String?
    let sizeText: String?
    let imageUrl: String?
    let bestPrice: Double
    let bestUnitPriceLabel: String?
    let storeCount: Int
    let offers: [IBGCandidate]

    enum CodingKeys: String, CodingKey {
        case id, title, brand, offers
        case sizeText = "size_text"
        case imageUrl = "image_url"
        case bestPrice = "best_price"
        case bestUnitPriceLabel = "best_unit_price_label"
        case storeCount = "store_count"
    }
}

struct IBGProviderProgress: Codable {
    let providerName: String
    let state: IBGProviderRunState
    let resultCount: Int
    let errorMessage: String?
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case state
        case providerName = "provider_name"
        case resultCount = "result_count"
        case errorMessage = "error_message"
        case completedAt = "completed_at"
    }
}

struct IBGSearchProgress: Codable {
    let runId: Int
    let state: String
    let totalProviders: Int
    let completedProviders: Int
    let providers: [IBGProviderProgress]

    enum CodingKeys: String, CodingKey {
        case state, providers
        case runId = "run_id"
        case totalProviders = "total_providers"
        case completedProviders = "completed_providers"
    }
}

struct IBGListItem: Codable, Identifiable {
    let id: Int
    let rawText: String
    let state: IBGItemState
    let position: Int
    let recommended: IBGCandidate?
    let selectedCandidateId: Int?
    let searchProgress: IBGSearchProgress?

    enum CodingKeys: String, CodingKey {
        case id, state, position, recommended
        case rawText = "raw_text"
        case selectedCandidateId = "selected_candidate_id"
        case searchProgress = "search_progress"
    }
}

struct IBGShoppingList: Codable, Identifiable {
    let id: Int
    let name: String
    let items: [IBGListItem]
}

// MARK: - Basket plans

struct IBGBasketLine: Codable, Identifiable {
    var id: Int { listItemId }
    let listItemId: Int
    let needLabel: String
    let productTitle: String
    let brand: String?
    let price: Double
    let sizeText: String?
    let unitPriceLabel: String?

    enum CodingKeys: String, CodingKey {
        case brand, price
        case listItemId = "list_item_id"
        case needLabel = "need_label"
        case productTitle = "product_title"
        case sizeText = "size_text"
        case unitPriceLabel = "unit_price_label"
    }
}

struct IBGStoreBucket: Codable, Identifiable {
    var id: Int { storeId }
    let storeId: Int
    let storeName: String
    let lines: [IBGBasketLine]
    let total: Double

    enum CodingKeys: String, CodingKey {
        case lines, total
        case storeId = "store_id"
        case storeName = "store_name"
    }
}

struct IBGBasketPlan: Codable {
    let mode: String
    let buckets: [IBGStoreBucket]
    let total: Double
    let storeCount: Int

    enum CodingKeys: String, CodingKey {
        case mode, buckets, total
        case storeCount = "store_count"
    }
}

struct IBGAvailableStore: Codable, Identifiable {
    var id: Int { storeId }
    let storeId: Int
    let storeName: String
    let itemCount: Int
    let totalItems: Int

    enum CodingKeys: String, CodingKey {
        case storeId = "store_id"
        case storeName = "store_name"
        case itemCount = "item_count"
        case totalItems = "total_items"
    }
}

// MARK: - Settings & providers

struct IBGSettings: Codable {
    var optimizeMode: IBGOptimizeMode
    var preferredStore: String?
    var zipCode: String?
    var ignoreSponsored: Bool
    var perProviderLimit: Int
    var perItemLimit: Int

    enum CodingKeys: String, CodingKey {
        case optimizeMode = "optimize_mode"
        case preferredStore = "preferred_store"
        case zipCode = "zip_code"
        case ignoreSponsored = "ignore_sponsored"
        case perProviderLimit = "per_provider_limit"
        case perItemLimit = "per_item_limit"
    }
}

struct IBGSettingsPatch: Encodable {
    var optimizeMode: IBGOptimizeMode?
    var preferredStore: String?
    var zipCode: String?
    var ignoreSponsored: Bool?
    var perProviderLimit: Int?
    var perItemLimit: Int?

    enum CodingKeys: String, CodingKey {
        case optimizeMode = "optimize_mode"
        case preferredStore = "preferred_store"
        case zipCode = "zip_code"
        case ignoreSponsored = "ignore_sponsored"
        case perProviderLimit = "per_provider_limit"
        case perItemLimit = "per_item_limit"
    }
}

struct IBGProvider: Codable, Identifiable {
    let id: Int
    let name: String
    let displayName: String
    let enabled: Bool
    let locationMode: IBGLocationMode
    let locationStatus: IBGLocationStatus
    let selectedStoreId: String?
    let selectedStoreLabel: String?
    let selectedStoreName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, enabled
        case displayName = "display_name"
        case locationMode = "location_mode"
        case locationStatus = "location_status"
        case selectedStoreId = "selected_store_id"
        case selectedStoreLabel = "selected_store_label"
        case selectedStoreName = "selected_store_name"
    }
}

struct IBGProviderStoreOption: Codable, Identifiable {
    var id: String { externalStoreId }
    let externalStoreId: String
    let storeName: String
    let locationLabel: String

    enum CodingKeys: String, CodingKey {
        case externalStoreId = "external_store_id"
        case storeName = "store_name"
        case locationLabel = "location_label"
    }
}

// MARK: - Health & Identity (Coolify deploy spec, 2026-04-18)

/// `GET /api/v1/healthz` — unauthenticated. Used by `IBuyGroceryClient.ping()`
/// and by the Settings UI's "Save & Test" button.
struct IBGHealth: Codable {
    let ok: Bool
    let version: String?
}

/// `GET /api/v1/auth/me` — requires `X-API-Key` (iOS) or NextAuth session
/// cookie (web). Used to render the "signed in as …" badge in Settings.
struct IBGUserMe: Codable {
    let email: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName = "display_name"
    }
}

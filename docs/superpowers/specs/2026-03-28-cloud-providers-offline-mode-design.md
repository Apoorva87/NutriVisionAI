# Cloud Providers, Offline Mode, Dashboard Compact & Scan Fix

## Goal

Transform NutriVisionAI from a thin client requiring a backend for everything into a standalone app that works with cloud AI providers (OpenAI, Gemini) without needing the Python backend. Add local meal persistence, bundle the nutrition database, compact the dashboard UI, and fix the scan page's provider routing.

## Architecture Shift

**Important:** This design deliberately changes the iOS app from a "thin client / UI shell" (as documented in `ios/CLAUDE.md`) to a hybrid app with local business logic for cloud provider modes. The `ios/CLAUDE.md` must be updated to reflect this new architecture. The "no business logic in Swift" principle now applies only to backend/LMStudio mode.

Two operating modes:

- **Cloud mode** (OpenAI/Gemini): iOS calls cloud API directly, nutrition lookups from bundled local DB, meals saved to local SQLite. No backend needed.
- **Local server mode** (LMStudio): Routes through Python backend for vision/portion/nutrition/meals. Same as current behavior.

```
CLOUD MODE:                          LOCAL SERVER MODE:
iOS -> OpenAI/Gemini (vision)        iOS -> Backend -> LMStudio (vision)
iOS -> Local SQLite (nutrition)      iOS -> Backend (nutrition + meals)
iOS -> Local SQLite (meals)
iOS -> Local SQLite (dashboard)
```

The app detects which mode based on the selected provider in Settings. Cloud providers use local persistence; LMStudio uses backend persistence.

## Tech Stack

- **iOS**: SwiftUI, Foundation networking (no external deps), SQLite via `sqlite3` C API (already available on iOS)
- **Backend**: FastAPI, OpenAI Python SDK (`openai`), Google GenAI SDK (`google-generativeai`)
- **Database**: SQLite (bundled ~1MB, 7,850 foods)

---

## Section 1: Bundled Nutrition Database

### What

Export the backend's nutrition_items table as a SQLite file. Bundle it in the iOS app. Provide a Swift class for lookups.

### Files

- `ios/NutriVisionAI/Data/nutrition.db` — bundled SQLite file (exported from backend)
- `ios/NutriVisionAI/Services/NutritionDB.swift` — Swift wrapper

### Schema (bundled DB)

```sql
CREATE TABLE nutrition_items (
    id INTEGER PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    serving_grams REAL NOT NULL,
    calories REAL NOT NULL,
    protein_g REAL NOT NULL,
    carbs_g REAL NOT NULL,
    fat_g REAL NOT NULL,
    source_label TEXT
);

CREATE TABLE nutrition_aliases (
    alias TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL
);
```

### NutritionDB API

```swift
/// Nutrition info for a food item at a specific gram amount.
/// Reuses the same field names as AnalysisItem for consistency.
struct LocalNutritionInfo {
    let canonicalName: String
    let servingGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let sourceLabel: String
}

final class NutritionDB {
    static let shared = NutritionDB()

    /// Search foods by name (fuzzy prefix match). Returns FoodItem structs
    /// constructed from SQLite rows (not Codable-decoded).
    func search(query: String, limit: Int = 15) -> [FoodItem]

    /// Look up nutrition for a canonical name at a given gram amount.
    /// Returns nil if the food is not in the database.
    /// Scales per-serving nutrition proportionally to the gram amount.
    func lookup(canonicalName: String, grams: Double) -> LocalNutritionInfo?

    /// Resolve an alias to its canonical name. Returns the input unchanged
    /// if no alias is found.
    func resolveAlias(_ name: String) -> String
}
```

**FoodItem construction:** `search()` constructs `FoodItem` structs directly from SQLite column values (not via JSON decoding). The `FoodItem` struct's `init` must support direct construction in addition to `Codable`.

- On first launch, copies bundled DB from app bundle to Documents directory
- Uses `sqlite3` C API directly (no external dependency)
- Thread-safe via serial dispatch queue

### Export Script

- `ios/scripts/export_nutrition_db.py` — reads from backend's `app.db`, writes `nutrition.db` with just the two tables above
- Run once manually; the exported file is checked into the repo
- Re-run if backend nutrition data changes (e.g., via admin import or AI food lookup saves)

---

## Section 2: Local Meal Persistence

### What

A local SQLite store for meals when using cloud providers. Separate from the nutrition DB.

### Files

- `ios/NutriVisionAI/Services/LocalMealStore.swift`

### Schema (in app Documents directory, `meals.db`)

```sql
CREATE TABLE meals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    meal_name TEXT NOT NULL,
    image_path TEXT,
    total_calories REAL DEFAULT 0,
    total_protein_g REAL DEFAULT 0,
    total_carbs_g REAL DEFAULT 0,
    total_fat_g REAL DEFAULT 0,
    created_at TEXT NOT NULL
);

CREATE TABLE meal_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    meal_id INTEGER NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
    detected_name TEXT NOT NULL,
    canonical_name TEXT NOT NULL,
    portion_label TEXT,
    estimated_grams REAL,
    calories REAL,
    protein_g REAL,
    carbs_g REAL,
    fat_g REAL,
    confidence REAL
);
```

**Image storage:** Images are saved as JPEG files (compressed to 0.5 quality, ~100-200KB each) in the app's Documents/MealImages/ directory. The `image_path` column stores the relative filename. This avoids SQLite bloat from multi-MB BLOBs.

### LocalMealStore API

```swift
final class LocalMealStore {
    static let shared = LocalMealStore()

    /// Save a meal with its items. Each item already has nutrition populated
    /// from the cloud provider analysis + NutritionDB lookup.
    /// Returns the new meal ID.
    func saveMeal(name: String, image: UIImage?, items: [AnalysisItem]) -> Int

    func deleteMeal(id: Int)

    func recentMeals(limit: Int = 10) -> [MealRecord]

    /// Compute today's calorie/macro totals from local meals.
    /// Reads goals from UserDefaults (same keys used by SettingsView).
    func todaySummary() -> DashboardSummary

    /// Compute history with daily trends, grouped meals, and top foods.
    /// SQL: GROUP BY date(created_at), aggregate sums, ORDER BY count for top foods.
    func history(days: Int = 14) -> HistoryResponse
}
```

**Goal source for todaySummary():** In cloud mode, calorie/macro goals are read from UserDefaults (the same `calorieGoal`, `proteinGoal`, `carbsGoal`, `fatGoal` state vars that SettingsView already persists). No backend settings fetch needed.

**todaySummary() SQL:**
```sql
SELECT COALESCE(SUM(total_calories), 0), COALESCE(SUM(total_protein_g), 0),
       COALESCE(SUM(total_carbs_g), 0), COALESCE(SUM(total_fat_g), 0)
FROM meals WHERE date(created_at) = date('now')
```

**history() SQL for trends:**
```sql
SELECT date(created_at) as day, SUM(total_calories), SUM(total_protein_g),
       SUM(total_carbs_g), SUM(total_fat_g)
FROM meals WHERE created_at >= date('now', '-14 days')
GROUP BY date(created_at) ORDER BY day
```

**history() SQL for top foods:**
```sql
SELECT canonical_name, COUNT(*) as cnt, SUM(calories) as total_cal
FROM meal_items mi JOIN meals m ON mi.meal_id = m.id
WHERE m.created_at >= date('now', '-14 days')
GROUP BY canonical_name ORDER BY cnt DESC LIMIT 10
```

- Returns the same model types (`MealRecord`, `DashboardSummary`, `HistoryResponse`) as the API client
- Dashboard/history views check the current mode and read from either `APIClient` or `LocalMealStore`

---

## Section 3: OpenAI Vision Provider (Backend)

### What

Add OpenAI as a backend vision provider so LMStudio-mode users can also select OpenAI through the backend pipeline.

### Files

- `app/providers/openai_provider.py` — new file
- `app/services.py` — wire into `build_provider_bundle()`

### OpenAI Provider

```python
class OpenAIVisionProvider(VisionProvider):
    def __init__(self, api_key: str, model: str = "gpt-4o-mini"):
        self.client = openai.OpenAI(api_key=api_key)
        self.model = model

    def detect_food_items(self, image_path: Path) -> List[Dict]:
        # Encode image as base64 via image_file_to_data_url()
        # Send to chat completions with vision
        # Parse JSON response via parse_json_object() / extract_list_payload()
        ...

class OpenAIPortionEstimator(PortionEstimator):
    def __init__(self, api_key: str, model: str = "gpt-4o-mini"):
        ...

    def estimate_portions(self, items, image_path=None) -> List[Dict]:
        # Send detected items + image to OpenAI
        # Get portion estimates back
        ...
```

### Settings

The API key is stored in the backend settings table as `openai_api_key`. The iOS app sends it via `PUT /settings`. The `build_provider_bundle()` reads it for `provider_name == "openai"`.

### Wire-up in services.py

```python
elif provider_name == "openai":
    api_key = settings.get("openai_api_key", "")
    if not api_key:
        raise RemoteProviderUnavailable("OpenAI API key not configured in settings")
    model = settings.get("openai_model", "gpt-4o-mini")
    vision_provider = OpenAIVisionProvider(api_key, model)
    portion_estimator = OpenAIPortionEstimator(api_key, model)
```

---

## Section 4: Gemini Vision Provider (Backend)

### What

Same as OpenAI but for Google Gemini. Free tier available.

### Files

- `app/providers/gemini_provider.py` — new file
- `app/services.py` — wire into `build_provider_bundle()`

### Gemini Provider

```python
class GeminiVisionProvider(VisionProvider):
    def __init__(self, api_key: str, model: str = "gemini-2.0-flash"):
        ...

    def detect_food_items(self, image_path: Path) -> List[Dict]:
        # Use google.generativeai client
        # Send image + prompt
        # Parse JSON response
        ...

class GeminiPortionEstimator(PortionEstimator):
    ...
```

### Wire-up

```python
elif provider_name == "google":
    api_key = settings.get("google_api_key", "")
    if not api_key:
        raise RemoteProviderUnavailable("Google API key not configured in settings")
    model = settings.get("google_model", "gemini-2.0-flash")
    vision_provider = GeminiVisionProvider(api_key, model)
    portion_estimator = GeminiPortionEstimator(api_key, model)
```

---

## Section 5: OpenAI Direct Provider (iOS)

### What

iOS-native OpenAI provider. Calls OpenAI API directly from the app without going through the backend. Uses bundled nutrition DB for lookups.

### Files

- `ios/NutriVisionAI/Services/OpenAIAnalysisProvider.swift`

### Flow

1. Read API key from Keychain (`openai_api_key`)
2. Read model from UserDefaults (`openai_model`, default `gpt-4o-mini`)
3. Encode image as base64
4. Send to OpenAI chat completions with vision prompt requesting JSON with food items + portions
5. Parse response JSON into detected items
6. For each item, resolve alias via `NutritionDB.shared.resolveAlias()`, then look up nutrition from `NutritionDB.shared.lookup(canonicalName:grams:)`
7. If `NutritionDB.lookup()` returns nil (food not in DB), include the item with `dbMatch: false` and zero nutrition — the user can still edit/remove it in the results view
8. Return `AnalysisResponse`

### Error handling

- **401/403 from OpenAI**: Throw `AnalysisError.providerUnavailable("Invalid OpenAI API key. Check Settings.")` — surfaced to user in the error state view
- **Malformed JSON**: Try `parse_json_object` style extraction (find first `{`, match balanced braces). If that fails, throw `AnalysisError.parsingFailed`
- **Network timeout**: Throw `AnalysisError.networkError` — user sees retry button

### Prompt

The prompt asks for food detection AND portion estimation in a single call (saves money vs. two calls):

```
Analyze this food photo. For each food item visible:
1. Identify the food (detected_name and canonical_name)
2. Estimate portion in grams
3. Rate your confidence (0.0-1.0)

Return JSON: {"items": [{"detected_name": "...", "canonical_name": "...", "portion_label": "...", "estimated_grams": 150.0, "confidence": 0.85}]}
```

Nutrition (calories/macros) is NOT requested from OpenAI — it comes from the local DB lookup, which is more accurate.

---

## Section 6: Gemini Direct Provider (iOS)

### What

Same as OpenAI provider but calls Gemini API. Free tier.

### Files

- `ios/NutriVisionAI/Services/GeminiAnalysisProvider.swift`

### Flow

Identical to OpenAI provider but uses Gemini's REST API:
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- Auth: API key as query parameter (`?key=...`)
- Image sent as inline base64 in the request body (`inlineData` with `mimeType` and `data`)
- Same prompt and same response parsing logic as OpenAI provider
- Same error handling patterns

### Error handling for rate limits

If Gemini returns 429 (rate limited on free tier), show user-facing error: "Gemini rate limit reached. Free tier allows 15 requests per minute. Please wait a moment." No automatic retry — the user taps "Try Again" when ready.

### Model

Default: `gemini-2.0-flash` (free tier: 15 RPM, 1M tokens/day)

---

## Section 7: FoodAnalysisService Refactor

### What

Update the provider routing to support all four provider types and integrate with Settings.

### Current providers

```swift
enum AnalysisProviderType: String, CaseIterable, Identifiable {
    case backend = "Backend API"
    case appleFoundation = "Apple Foundation Models"
}
```

### New providers

```swift
enum AnalysisProviderType: String, CaseIterable, Identifiable {
    case backend = "Backend API"           // LMStudio through backend
    case openai = "OpenAI"                 // Direct to OpenAI from iOS
    case gemini = "Google Gemini"          // Direct to Gemini from iOS
    case appleFoundation = "Apple Foundation Models"  // On-device (iOS 26+)
}
```

**Migration note:** The raw values are changing for the new cases. The existing `"Backend API"` and `"Apple Foundation Models"` raw values are preserved. Old UserDefaults values remain valid.

### Provider selection

The provider is determined by the `modelProvider` setting (synced from SettingsView):
- `"lmstudio"` or `"ollama"` -> `.backend`
- `"openai"` -> `.openai`
- `"google"` -> `.gemini`
- Apple Foundation -> `.appleFoundation` (only in AppleAI build)

When the user selects a provider in Settings and saves, `FoodAnalysisService.currentProvider` updates automatically.

### Cloud mode detection

A helper property on `FoodAnalysisService`:

```swift
var isCloudMode: Bool {
    switch currentProvider {
    case .openai, .gemini, .appleFoundation: return true
    case .backend: return false
    }
}
```

### Meal saving routing

- `.backend` mode: save via `APIClient.shared.createMeal()`
- `.openai` / `.gemini` / `.appleFoundation` mode: save via `LocalMealStore.shared.saveMeal()`

This routing happens in `AnalyzeView.saveMeal()` and in `LogView`.

### Dashboard/History routing

- `.backend` mode: fetch from `APIClient`
- Cloud modes: fetch from `LocalMealStore`

This routing happens in `DashboardView.loadDashboard()` and `HistoryView`.

---

## Section 8: Dashboard UI — Compact Calories & Macros

### What

Combine the calorie ring and macro bars into a single compact card. Reduce vertical space from ~400pt to ~140pt.

### Current layout

```
┌──────────────────────────┐
│    Today's Calories      │
│                          │
│      ┌────────┐          │
│      │  1200  │          │
│      │of 2200 │          │
│      └────────┘          │
│                          │
└──────────────────────────┘
┌──────────────────────────┐
│  Macros                  │
│  Protein ████░░░ 80/150g │
│  Carbs   ██████░ 140/200g│
│  Fat     ███░░░░ 35/65g  │
└──────────────────────────┘
```

### New layout

```
┌──────────────────────────────────┐
│ ┌──────┐  1200 / 2200 kcal      │
│ │      │  800 remaining          │
│ │ ring │  ───────────────────    │
│ │      │  Protein ████░░ 80/150g │
│ └──────┘  Carbs   █████░ 140/200│
│           Fat     ███░░░ 35/65g  │
└──────────────────────────────────┘
```

- Calorie ring: 100x100 (down from 200x200)
- Ring on the left, text + macro bars on the right
- Single card with `.themedCard(glow: true)`
- `CalorieSummaryCard` and `MacroProgressSection` merged into one `CompactDashboardCard`
- Remove the separate `CalorieSummaryCard` and `MacroProgressSection` structs (replaced by `CompactDashboardCard`)

---

## Section 9: Dashboard Section Reorder

### Current order

1. CalorieSummaryCard
2. MacroProgressSection
3. RecentMealsSection
4. MealSuggestionsView

### New order

1. CompactDashboardCard (calories + macros combined)
2. MealSuggestionsView (AI suggestions — this view already exists at `Views/Components/MealSuggestionsView.swift`)
3. RecentMealsSection

---

## Section 10: Scan Page Fix

### Problem

The scan page sends images to the backend via `POST /api/v1/analysis`. The backend's `build_provider_bundle()` defaults to `StubVisionProvider` when the configured provider (e.g., `"openai"`) isn't recognized. The stub returns hardcoded "chicken breast + rice" regardless of the image.

### Fixes

1. **Backend**: When `provider_name` is `"openai"` or `"google"` but the API key is missing/empty, raise `RemoteProviderUnavailable` with a clear error message (e.g., "OpenAI API key not configured"). The API endpoint catches this and returns HTTP 503. No silent fallback to stubs.

2. **iOS**: When `FoodAnalysisService.currentProvider` is `.openai` or `.gemini`, the scan page calls the cloud provider directly (not through the backend). This is already handled by the provider refactor in Section 7.

3. **Backend fallback**: Remove `StubVisionProvider` as a silent fallback. If the configured provider can't be initialized, raise an error. Stubs should only be used when `model_provider == "stub"` explicitly.

---

## Settings Changes

### Backend settings table additions

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `openai_api_key` | string | "" | OpenAI API key |
| `openai_model` | string | "gpt-4o-mini" | OpenAI model for vision |
| `google_api_key` | string | "" | Google Gemini API key |
| `google_model` | string | "gemini-2.0-flash" | Gemini model |

### iOS SettingsPayload additions

Add `openaiApiKey`, `openaiModel`, `googleApiKey`, `googleModel` fields to `SettingsPayload`. These are sent to the backend via `PUT /settings` so the backend can also use them in server mode.

For cloud (direct) mode, the iOS app reads API keys from Keychain directly and doesn't need the backend to store them.

### iOS SettingsView model list update

Update the Gemini model picker options to include current models: `"gemini-2.0-flash"`, `"gemini-2.0-flash-lite"`, `"gemini-1.5-pro"`. Remove any stale model names.

### iOS goal persistence for cloud mode

SettingsView already stores goals in `@State` vars backed by string fields. For cloud mode, also persist goals to UserDefaults on save:
- `UserDefaults.standard.set(calorieGoal, forKey: "local_calorie_goal")`
- Same for protein, carbs, fat goals
- `LocalMealStore.todaySummary()` reads from these keys

---

## What's NOT in scope

- Sync between local and backend meal stores
- Migration of backend meals to local or vice versa
- Anthropic provider (user hasn't indicated they have an API key)
- Offline settings (settings still stored in UserDefaults, not synced)
- Nutrition DB updates (the bundled DB is static; future feature to refresh it)

---

## Testing

- Backend: `pytest` for OpenAI/Gemini providers (mock API calls)
- iOS: Manual testing — build, select each provider, scan a food photo, verify results
- Nutrition DB: Verify export script produces correct SQLite, verify iOS lookups match backend lookups

---

## CLAUDE.md Updates Required

After implementation, update `ios/CLAUDE.md` to reflect:
- The app is no longer purely a UI shell in cloud mode
- Two operating modes (cloud vs. backend)
- New files: NutritionDB, LocalMealStore, OpenAI/Gemini providers
- `FoodAnalysisService` as the central routing layer

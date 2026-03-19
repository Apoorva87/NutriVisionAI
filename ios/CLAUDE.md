# NutriVisionAI — iOS App

SwiftUI app targeting **iOS 17+**. This is a thin client — all business logic, AI/LLM processing, and data persistence live in the Python backend. The iOS app is purely UI + networking.

## What This App Does

NutriVisionAI is a nutrition tracking app. Users can:
1. **Scan food photos** — camera captures a meal, AI detects food items and estimates nutrition
2. **Quick log meals** — search a nutrition database, build a meal from items, save it
3. **View dashboard** — today's calorie/macro summary, recent meals
4. **Browse history** — 14-day trends, meals grouped by day, top foods
5. **Manage settings** — calorie/macro goals, AI provider config
6. **Custom foods** — create user-specific food entries, log them as meals
7. **AI food lookup** — ask the LLM to estimate nutrition for unknown foods

## Project Structure

```
ios/NutriVisionAI/
├── NutriVisionAIApp.swift          # @main entry point
├── Models/
│   └── NutritionModels.swift       # All Codable structs (API contract)
├── Services/
│   └── APIClient.swift             # Singleton HTTP client (Bearer token auth)
├── Views/
│   └── ContentView.swift           # Tab-based navigation (placeholder views)
├── Supporting/                     # (empty — for assets, Info.plist, etc.)
├── project.yml                     # XcodeGen spec (run `xcodegen generate`)
└── Package.swift                   # SPM reference (alternative to xcodeproj)
```

## Building the Xcode Project

Option 1 — XcodeGen (recommended):
```bash
brew install xcodegen
cd ios/NutriVisionAI
xcodegen generate
open NutriVisionAI.xcodeproj
```

Option 2 — Manual:
1. Xcode → File → New → Project → iOS App (SwiftUI, Swift)
2. Save into `ios/NutriVisionAI/`
3. Drag `Models/`, `Services/`, `Views/` into the project navigator

No external dependencies. Pure Foundation networking + SwiftUI.

## Connecting to the Backend

The backend is a Python FastAPI server. During development:

```bash
# In the repo root:
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The iOS app connects to `http://<your-mac-ip>:8000`. Set the base URL in `APIClient.shared.baseURL`. For the simulator, `http://localhost:8000` works. For a physical device, use your Mac's local IP (e.g. `http://192.168.1.42:8000`).

**Important**: iOS requires App Transport Security exceptions for HTTP (non-HTTPS) connections. Add to Info.plist:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

## Authentication Flow

The backend uses session tokens. The iOS app uses Bearer token auth.

1. **Login**: `POST /api/v1/auth/login` with JSON `{"name": "...", "email": "..."}`
   - Response: `{"token": "abc123...", "expires_at": "2026-04-17T...", "user": {"id": 1, "name": "...", "email": "..."}}`
   - Store the `token` — send it as `Authorization: Bearer <token>` on all subsequent requests
   - Token expires after 30 days
2. **Check current user**: `GET /api/v1/auth/me` → `{"id": 1, "name": "...", "email": "...", "is_system": false}`
3. **Logout**: `POST /api/v1/auth/logout` → `{"ok": true}`
4. **No token / expired token**: API falls back to "Default User" (a system user). The app still works but data isn't user-scoped.

Token is currently stored in UserDefaults. For production, move to Keychain.

## Complete API Reference

Base URL: `{baseURL}/api/v1`

All requests that need auth: include `Authorization: Bearer <token>` header.
All POST/PUT bodies are JSON (`Content-Type: application/json`) unless noted as multipart.
All responses are JSON. Errors return `{"error": "message"}` with appropriate HTTP status.

### Auth

| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/auth/login` | `{"name": str, "email": str}` | `{"token": str, "expires_at": str, "user": UserInfo}` |
| POST | `/auth/logout` | (empty) | `{"ok": true}` |
| GET | `/auth/me` | — | `UserInfo` |

### Dashboard

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/dashboard` | — | `{"summary": DashboardSummary, "recent_meals": [MealRecord], "user": UserInfo}` |

### Meals

| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/meals` | `{"meal_name": str, "image_path"?: str, "items": [MealItemInput]}` | `{"meal_id": int, "totals": NutritionTotals, "dashboard": DashboardSummary}` |
| GET | `/meals` | query: `?limit=10` | `{"meals": [MealRecord]}` |
| GET | `/meals/{id}` | — | Full meal detail with items |
| PUT | `/meals/{id}` | `{"meal_name"?: str, "items"?: [...]}` | Updated meal |
| DELETE | `/meals/{id}` | — | `{"ok": true}` |

**MealItemInput shape** (for creating meals):
```json
{
  "detected_name": "chicken breast",
  "canonical_name": "chicken breast",
  "portion_label": "medium",
  "estimated_grams": 150.0,
  "uncertainty": "low",
  "confidence": 0.9
}
```
The backend resolves `canonical_name` against the nutrition DB and calculates calories/macros server-side. If `canonical_name` doesn't match any known food, the API returns 400.

### Food Search

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/foods` | query: `?q=chicken&limit=15` | `{"items": [FoodItem]}` |

**FoodItem shape**:
```json
{
  "canonical_name": "chicken breast",
  "serving_grams": 100.0,
  "calories": 165.0,
  "protein_g": 31.0,
  "carbs_g": 0.0,
  "fat_g": 3.6,
  "source_label": "USDA"
}
```

### Image Analysis

| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/analysis` | **multipart/form-data** with field `image` (JPEG/PNG file) | `AnalysisResponse` |

**This is the only multipart endpoint.** All others use JSON.

Response shape:
```json
{
  "image_path": "/uploads/abc123.jpg",
  "items": [AnalysisItem],
  "totals": {"calories": 450.0, "protein_g": 35.0, "carbs_g": 40.0, "fat_g": 15.0},
  "provider_metadata": {"provider": "lmstudio", "model": "..."}
}
```

Each `AnalysisItem` includes detection + portion + nutrition fields. Items may have `db_match: false` if the food isn't in the nutrition DB.

### History

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/history` | query: `?days=14&top_foods_limit=10` | `{"trends": [...], "grouped_meals": {...}, "top_foods": [...]}` |

`trends` is an array of daily summaries (date, calories, protein_g, carbs_g, fat_g).
`grouped_meals` is a dict keyed by date string → array of MealRecord.
`top_foods` is an array of `{canonical_name, count, total_calories, ...}`.

### Custom Foods

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/custom-foods` | query: `?limit=50` | `{"items": [CustomFood]}` |
| POST | `/custom-foods` | `CustomFoodInput` JSON | `{"ok": true}` |
| DELETE | `/custom-foods/{id}` | — | `{"ok": true}` |
| POST | `/custom-foods/{id}/log` | `{"meal_name": str, "servings"?: float}` | `{"ok": true, "meal_id": int}` |

**CustomFoodInput shape**:
```json
{
  "food_name": "Homemade granola",
  "serving_grams": 50.0,
  "calories": 220.0,
  "protein_g": 5.0,
  "carbs_g": 30.0,
  "fat_g": 10.0,
  "source_label": "",
  "source_reference": "",
  "source_notes": ""
}
```

### Settings

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/settings` | — | Settings dict |
| PUT | `/settings` | `SettingsPayload` JSON | `{"settings": {...}, "dashboard": DashboardSummary}` |

**SettingsPayload shape**:
```json
{
  "current_user_name": "default",
  "calorie_goal": 2200,
  "protein_g": 160,
  "carbs_g": 220,
  "fat_g": 70,
  "model_provider": "lmstudio",
  "portion_estimation_style": "quick",
  "lmstudio_base_url": "http://localhost:1234",
  "lmstudio_vision_model": "qwen/qwen3-vl-8b",
  "lmstudio_portion_model": "qwen/qwen3-vl-8b"
}
```

### LLM / AI Food Lookup

| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/llm/chat` | `{"model": str, "messages": [...], "temperature"?: float}` | LLM completion response |
| POST | `/llm/food-lookup` | `{"query": "pad thai", "web_search"?: bool}` | `{"query": str, "ai_estimate"?: {...}, "web_result"?: {...}}` |
| POST | `/llm/food-lookup/save` | `{"food_name": str, "serving_grams": float, "calories": float, "protein_g": float, "carbs_g": float, "fat_g": float}` | `{"ok": true, "item_id": int, "canonical_name": str}` |

**AI food lookup response shape** (ai_estimate / web_result):
```json
{
  "food_name": "pad thai",
  "serving_grams": 300,
  "calories": 450.0,
  "protein_g": 15.0,
  "carbs_g": 55.0,
  "fat_g": 18.0,
  "confidence": 0.7,
  "notes": "Estimate based on typical restaurant portion",
  "source": "ai_estimate"
}
```

### Admin (optional — for power users)

| Method | Path | Body | Response |
|--------|------|------|----------|
| GET | `/admin/nutrition-items?q=...&limit=100` | — | `{"items": [...]}` |
| GET | `/admin/nutrition-items/{id}` | — | Nutrition item |
| POST | `/admin/nutrition-items` | JSON with nutrition fields | `{"ok": true, "item_id": int}` |
| DELETE | `/admin/nutrition-items/{id}` | — | `{"ok": true}` |
| GET | `/admin/users` | — | `{"users": [...]}` |
| GET | `/admin/db-overview` | — | DB statistics |
| POST | `/admin/label-import` | **multipart** with `image` + `custom_name` + `target_scope` | `{"ok": true, ...}` |

## Swift Model ↔ Python Schema Mapping

All Swift models are in `Models/NutritionModels.swift`. They map to Python Pydantic models in `../app/schemas.py`.

| Swift Struct | Python Class | Used By |
|-------------|-------------|---------|
| `LoginRequest` | `AuthPayload` | POST /auth/login |
| `LoginResponse` | (inline) | POST /auth/login response |
| `UserInfo` | `UserRecord` (subset) | /auth/me, /dashboard |
| `DashboardResponse` | (inline) | GET /dashboard |
| `DashboardSummary` | `DashboardSummary` | GET /dashboard |
| `MacroGoals` | (nested dict) | Inside DashboardSummary |
| `NutritionTotals` | `NutritionTotals` | Meals, analysis |
| `MealRecord` | `MealRecord` | GET /meals, /dashboard |
| `MealItemInput` | `MealItemInput` | POST /meals |
| `CreateMealRequest` | (inline) | POST /meals |
| `CreateMealResponse` | (inline) | POST /meals response |
| `FoodItem` | (inline from DB row) | GET /foods |
| `FoodSearchResponse` | (inline) | GET /foods |
| `AnalysisItem` | `AnalysisItem` | POST /analysis |
| `AnalysisResponse` | `AnalysisResult` | POST /analysis |
| `CustomFood` | `CustomFoodRecord` (subset) | GET /custom-foods |
| `APIError` | (inline) | All error responses |

**Convention**: Python uses `snake_case`, Swift uses `camelCase`. Every Swift struct has `CodingKeys` that map between them. When adding new fields, always add the `CodingKey` mapping.

## Key Design Decisions for the iOS Agent

1. **No business logic in Swift** — don't calculate nutrition, don't validate food names against a local DB. The backend does all of this. The app is a UI shell.

2. **APIClient is the single networking layer** — all HTTP goes through `Services/APIClient.swift`. Don't create separate networking code.

3. **Image upload uses multipart** — only `POST /analysis` and `POST /admin/label-import` use multipart form data. Everything else is JSON.

4. **Food items use `canonical_name` as the key** — when building a meal, the `canonical_name` must match a food in the backend nutrition database. Use the `/foods` search endpoint to find valid names.

5. **The dashboard refreshes after saving a meal** — the `POST /meals` response includes an updated `dashboard` object so the UI can update without a separate fetch.

6. **Tab structure mirrors the web app** — 5 tabs: Home (dashboard), Scan (camera → analysis), Log (search + build meal), History (trends), Settings.

7. **Uploaded images are served from the backend** — `image_path` values like `/uploads/abc123.jpg` are relative to the backend base URL. To display a meal photo: `URL(string: "\(APIClient.shared.baseURL)\(imagePath)")`.

## Screens to Build

Each tab corresponds to a screen. Here's what each needs:

### 1. Dashboard (Home tab)
- Call `GET /dashboard` on appear
- Show: calorie ring/progress, macro bars (protein/carbs/fat), recent meals list
- Tap a meal → navigate to meal detail (call `GET /meals/{id}`)
- Delete meal via swipe (call `DELETE /meals/{id}`)

### 2. Scan (camera tab)
- Camera capture or photo library picker
- Send image to `POST /analysis` (multipart)
- Show detected items with nutrition
- User can edit items, remove items, adjust portions
- Save → `POST /meals` with the item list

### 3. Log (quick add tab)
- Search bar → `GET /foods?q=...` (debounced)
- Show search results as selectable list
- User builds a "meal builder" — add items, set grams
- Custom foods section → `GET /custom-foods`
- AI food lookup → `POST /llm/food-lookup`
- Save → `POST /meals`

### 4. History
- Call `GET /history?days=14`
- Show daily calorie trend chart
- Expandable day sections with meals
- Top foods section

### 5. Settings
- Call `GET /settings` on appear
- Form: calorie goal, macro targets, AI provider config
- Login/logout section using `/auth/login` and `/auth/logout`
- Server URL configuration (update `APIClient.shared.baseURL`)
- Save → `PUT /settings`

## Error Handling

All API errors return `{"error": "human-readable message"}` with HTTP status codes:
- 400 = bad input (show message to user)
- 401 = not authenticated (prompt login)
- 404 = not found
- 502/503 = AI provider unavailable (show "AI service offline" message)

The `APIClient` already decodes these into `NutriError.api(statusCode:message:)`.

## Testing the API

The backend has auto-generated API docs. Open in a browser:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

You can test every endpoint interactively from the Swagger UI before writing Swift code.

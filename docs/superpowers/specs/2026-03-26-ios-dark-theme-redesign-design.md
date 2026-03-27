# iOS App Dark Theme Redesign — Design Spec

## Overview

Visual refresh of the NutriVisionAI iOS app with a "Neon Vitality" dark theme plus layout polish and new features. The backend stays unchanged. All AI/LLM calls route through the backend's existing `/api/v1/llm/chat` and `/api/v1/analysis` endpoints — the iOS app remains a thin UI client per the project's architectural rules.

**Theme:** True black backgrounds (#0f0f0f) with purple/violet gradient accents, gradient macro colors, glowing card effects. Bold, modern, fitness-app energy.

**Scope:** Theme layer + layout polish + 3 new features (AI suggestions, portion controls, multi-provider settings).

## Color System

All colors centralized in a new `Theme.swift` file. Views reference semantic color names, never hardcoded values.

| Token | Value | Usage |
|-------|-------|-------|
| `background` | `#0f0f0f` | Main app background |
| `cardSurface` | `white 3% opacity` | Card/section backgrounds |
| `cardBorder` | `white 6% opacity` | Card borders |
| `cardGlow` | `violet-400 12% opacity` | Highlighted card borders |
| `accent` | `#a78bfa` (violet-400) | Primary accent, tab highlight, checkmarks |
| `accentGradient` | `#7c3aed → #a855f7` | Buttons, active pills, tab glow |
| `textPrimary` | `#e2e8f0` | Primary text |
| `textSecondary` | `#94a3b8` | Labels, captions |
| `textMuted` | `#475569` | Timestamps, hints |
| `proteinGradient` | `#38bdf8 → #818cf8` | Protein bars/values (sky → indigo) |
| `carbsGradient` | `#facc15 → #fb923c` | Carbs bars/values (yellow → orange) |
| `fatGradient` | `#fb7185 → #e879f9` | Fat bars/values (rose → fuchsia) |
| `positive` | `#22d3ee` (cyan) | "Remaining" text, positive states |
| `destructive` | `#ef4444` | Delete, logout, remove actions |
| `success` | `#22c55e → #16a34a` | Checkmarks, add buttons (green gradient) |
| `calorieValue` | `#c084fc` (violet-300) | Calorie number highlights |

## Files to Create

| File | Purpose |
|------|---------|
| `Views/Theme.swift` | Centralized color/style definitions |
| `Views/Components/PortionSelector.swift` | Reusable S/M/L/XL portion control |
| `Views/Components/GradientButton.swift` | Reusable gradient button component |
| `Views/MealSuggestionsView.swift` | AI meal plan section for dashboard |
| `Views/QuickFoodSearchSheet.swift` | Compact food search sheet for scan results |
| `Services/KeychainHelper.swift` | Simple Keychain wrapper for storing API keys |

## Files to Modify

| File | Changes |
|------|---------|
| `NutriVisionAIApp.swift` | Force dark mode via `.preferredColorScheme(.dark)`, set accent color |
| `Views/ContentView.swift` | Style tab bar with dark tint + violet accent |
| `Views/DashboardView.swift` | Apply theme colors, add MealSuggestionsView section |
| `Views/AnalyzeView.swift` | Theme all sub-views, add PortionSelector to results, add QuickFoodSearchSheet |
| `Views/LogView.swift` | Theme all sub-views, add PortionSelector to meal builder items |
| `Views/HistoryView.swift` | Theme colors, gradient chart bars, styled day pills |
| `Views/SettingsView.swift` | Theme colors, replace AI section with multi-provider cards, add provider detail sheets |
| `Services/APIClient.swift` | Add `llmChat` method for meal suggestions endpoint |
| `Models/NutritionModels.swift` | Add models for LLM chat request/response, provider config |

## Screen-by-Screen Specifications

### 1. Dashboard

**Existing behavior preserved:** Calorie ring, macro bars, recent meals, pull-to-refresh, meal detail sheet.

**Visual changes:**
- Calorie ring: violet gradient stroke with glow (`.shadow(color: Theme.accent.opacity(0.4), radius: 8)`)
- Ring background: `violet-400 10% opacity`
- "Remaining" text in cyan (`#22d3ee`) for positive, red for over
- Macro bars: gradient fills (protein=sky→indigo, carbs=yellow→orange, fat=rose→fuchsia)
- Cards: `cardSurface` background with `cardBorder`. Hero calorie card gets `cardGlow` border
- Meal thumbnails: gradient fallback backgrounds when no image (random from a set of dark gradients)
- Calorie values in `#c084fc` (violet-300, added as `calorieValue` token)
- Spring animation on ring progress (0.6s duration)

**New: AI Meal Suggestions section** (below Recent Meals):
- Section header: "Meal Plan" with sparkle icon + refresh button
- Controls row:
  - Craving text input (placeholder: "e.g. indian, pasta...")
  - Calorie budget display with +/- 100 kcal buttons (defaults to `summary.remainingCalories`)
- Suggestion cards grouped by meal slot:
  - Determines remaining meal slots based on device local time (breakfast <10am, lunch <2pm, snack <5pm, dinner <9pm)
  - Proportional calorie split: breakfast 20%, lunch 35%, snack 10%, dinner 35%
  - 2 options per slot shown side-by-side
  - Each option shows: food name, ingredients summary, macro breakdown (colored)
- Data flow: `POST /api/v1/llm/chat` with system prompt containing remaining calories, macros, recent meals, craving preference
- States: loading (shimmer skeleton), error (link to Settings), all meals done ("You're all set!"), budget < 50 ("You've hit your goal!")
- Auto-loads on dashboard appear, user can refresh manually

### 2. Scan

**Capture state** — visual changes only:
- Camera icon with violet glow (`.shadow(color: Theme.accent.opacity(0.3), radius: 20)`)
- "Take Photo" button: gradient (`accentGradient`) with glow shadow
- "Choose from Library" button: `cardSurface` with `cardBorder`
- Both buttons 14pt corner radius, full-width

**Analyzing state** — visual changes only:
- Black overlay with blur on captured image
- White progress spinner + "Analyzing..." text

**Results state** — visual + new features:

Visual:
- Nutrition summary banner: `violet-400 6% bg` with `violet-400 12% border`, colored macro values
- Detected items as discrete cards: `cardSurface` bg, green gradient checkmark, violet calorie text
- "Save Meal" gradient button with glow

New — Portion Selector per item:
- Row of 4 buttons below each detected item: S / M / L / XL
- Each shows size label + estimated weight in grams
- VLM's estimated weight = "M" (the 1x baseline)
- Multipliers: S=0.5x, M=1.0x, L=1.5x, XL=2.0x
- Active selection: `violet-400 12% bg` + `violet-400 30% border` + violet text
- Inactive: `white 4% bg` + `white 6% border` + muted text
- Selecting a portion updates `gramsMultiplier` on `EditableAnalysisItem`
- **Calorie/macro scaling formula:** All nutrition values on `AnalysisItem` are absolute (for the VLM-estimated weight). Scale by: `item.calories * gramsMultiplier` (and same for proteinG, carbsG, fatG). This works because the VLM estimate = 1.0x baseline.
- **Bug fix required:** The existing `AnalyzeView` totals compute `$1.item.calories` (raw, unscaled). Must change to `$1.item.calories * $1.gramsMultiplier` (and same for all macro totals). This fix applies to `totalCalories`, `totalProtein`, `totalCarbs`, `totalFat` computed properties.
- Nutrition banner updates live with `.numericText()` content transition
- Haptic feedback (`.light` impact) on selection

New — Quick food search:
- Dashed-border "Add more items from database..." button below item list
- Tapping opens `QuickFoodSearchSheet` (half-sheet):
  - Search bar → `GET /api/v1/foods?q=...`
  - Results list with name, serving, calories, macros, green "+" button
  - **FoodItem → AnalysisItem conversion:** When adding a DB food to scan results, create an `AnalysisItem` with:
    - `detectedName` = `canonicalName` (from FoodItem)
    - `canonicalName` = `canonicalName`
    - `portionLabel` = "1 serving"
    - `estimatedGrams` = `servingGrams`
    - `uncertainty` = "low"
    - `confidence` = 1.0 (user-selected from DB)
    - `calories/proteinG/carbsG/fatG` = values from FoodItem
    - `visionConfidence` = 0.0 (not vision-detected)
    - `dbMatch` = true
    - `nutritionAvailable` = true
  - Wrap in `EditableAnalysisItem` and append to `editableItems`
  - Item gets its own portion selector
- Use case: VLM missed a side, sauce, or drink

### 3. Log

**Existing behavior preserved:** Search, My Foods tab, meal builder, AI food lookup sheet.

**Visual changes:**
- Segmented control: `white 4% bg`, active segment `violet-400 15% bg` with violet text
- Search bar: `white 4% bg` with `white 6% border`, 12px corner radius
- Search results: green gradient "+" circles (28pt), macro text colored
- Meal builder card: `cardGlow` border, red "⊖" for remove
- Macro summary in colored text (blue/gold/pink)
- Save button: gradient capsule within builder
- AI Food Lookup button: violet-tinted pill with sparkle icon

**New — Portion selector in meal builder:**
- When a food is added to the builder, inline S/M/L/XL row appears below it
- For DB foods: base weight = `servingGrams` from the food item
  - S = 0.5x, M = 1.0x (default), L = 1.5x, XL = 2.0x
- Weight labels: `Int(servingGrams * multiplier)`
- Selecting a portion updates `grams` on `MealBuilderItem` and recalculates totals
- Same `PortionSelector` component as Scan results

### 4. History

**Existing behavior preserved:** Day selector, calorie chart, top foods, meals by day.

**Visual changes only:**
- Day selector pills: active = `accentGradient` bg with glow shadow, white text; inactive = `white 4% bg`
- Chart bars: vertical gradient (bottom `#6d28d9` → top `#a78bfa`); bars exceeding goal use warmer gradient (`#c084fc → #7c3aed`)
- Average rule mark: `violet-400 30% opacity` dashed line
- Top foods: gradient medal circles (gold, silver, bronze)
- Day cards: `cardSurface` bg, chevron rotation animation on expand
- Chart X-axis and Y-axis labels in `textMuted`

### 5. Settings

**Existing behavior preserved:** Account, nutrition goals, server URL, save button, login/logout.

**Visual changes:**
- Form background: forced dark
- Section headers: violet uppercase text (`#7c3aed`)
- Grouped rows: `cardSurface` bg with `white 4% border`, connected with -1px margin overlap
- User avatar: gradient initials circle (`accentGradient`)
- Save button: gradient style at bottom
- Success toast: `.ultraThinMaterial` with dark backdrop

**New — Multi-provider AI settings** (replaces current AI Configuration section):

Provider selector (replaces Picker):
- Vertical list of tappable provider cards:
  1. **Local Server** (LM Studio / Ollama) — icon: blue gradient
  2. **OpenAI** (GPT-4o, GPT-4o-mini) — icon: green gradient
  3. **Google** (Gemini 2.5 Flash/Pro) — icon: blue gradient
  4. **Anthropic** (Claude Sonnet 4, Haiku) — icon: orange gradient
- Active provider: `violet-400 6% bg` + `violet-400 30% border` + checkmark
- Inactive: `white 3% bg` + `white 6% border` + chevron

Local Server config (shown when Local is selected):
- Inline grouped rows: Base URL, Vision Model, Chat Model
- Same fields as current LM Studio section

Cloud provider config (shown on tap for OpenAI/Google/Anthropic):
- Opens a half-sheet with:
  1. API Key input (`SecureField`, stored in iOS Keychain via a `KeychainHelper`)
  2. Model picker (segmented or list of supported models)
  3. Optional base URL override (for proxy servers)
  4. "Test Connection" button
  5. "Save & Activate" gradient button
- API key stored locally in Keychain only — NOT sent to backend
- Model name saved to backend via `PUT /settings` (`model_provider` field)

**Architecture note — all providers route through backend:**
The iOS app remains a thin client. All AI/LLM calls go through the backend:
- Vision analysis: always `POST /api/v1/analysis` (multipart)
- Meal suggestions: always `POST /api/v1/llm/chat`
- The backend's existing `model_provider` field in settings controls which provider is used server-side

For this phase, the Settings UI shows all 4 provider cards, but:
- **Local Server** and **OpenAI** are fully functional (backend already supports them)
- **Google** and **Anthropic** cards are shown but tapping them displays a note: "Coming soon — requires backend support". They store the user's preference locally (UserDefaults) so the UI state persists, but actual API routing is deferred to a future backend update.
- API keys entered for cloud providers are stored in iOS Keychain for future use when backend support is added

The `FoodAnalysisService` existing provider abstraction (Backend vs Apple Foundation Models) is **separate** from this LLM/chat provider selection. Image analysis provider = how to process photos (backend API vs on-device Apple FM). LLM provider = which model the backend uses for chat/suggestions. Both are configured in Settings but in different sections.

## Shared Components

### `PortionSelector`
```
Input: baseGrams (Double), onSelect: (Double) -> Void
Options: S (0.5x), M (1.0x), L (1.5x), XL (2.0x)
Display: Size label + "~{grams}g"
State: selected multiplier
Style: horizontal row of 4 equal-width buttons
```
Used in: AnalyzeView (scan results), LogView (meal builder items)

### `GradientButton`
```
Input: title (String), icon (String?), isLoading (Bool), action: () -> Void
Style: accentGradient background, white text, 14px corner radius, glow shadow
```
Used in: Scan capture, Save Meal, Save Settings, provider detail sheet

### `Theme`
Static struct with all color/gradient/style definitions. No Color extension pollution — just `Theme.accent`, `Theme.cardSurface`, etc.

### `KeychainHelper`
```
Interface:
  static func save(key: String, value: String) throws
  static func read(key: String) -> String?
  static func delete(key: String) throws
Keys: "openai_api_key", "google_api_key", "anthropic_api_key"
```
Uses `Security` framework (`SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete`). Simple wrapper, no third-party dependencies.

## New Models (NutritionModels.swift)

```swift
// LLM Chat (for meal suggestions)
struct LLMChatRequest: Codable {
    let model: String
    let messages: [LLMMessage]
    let temperature: Double?
}

struct LLMMessage: Codable {
    let role: String  // "system" or "user"
    let content: String
}

// Backend /api/v1/llm/chat returns OpenAI-compatible response
struct LLMChatResponse: Codable {
    let choices: [LLMChoice]
}

struct LLMChoice: Codable {
    let message: LLMMessage
}

// Meal suggestion parsed from the JSON array inside the LLM content string.
// The LLM is prompted to return a JSON array of these objects.
// Parsing: decode LLMChatResponse → extract choices[0].message.content →
//          JSON-decode that string as [MealSuggestion]
struct MealSuggestion: Codable, Identifiable {
    var id: String { "\(meal)-\(option)" }
    let meal: String        // "breakfast", "lunch", "snack", "dinner"
    let option: Int
    let food: String
    let ingredients: String
    let reason: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case meal, option, food, ingredients, reason, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}
```

## New APIClient Methods

```swift
// Meal suggestions via LLM
func llmChat(model: String, messages: [LLMMessage], temperature: Double?) async throws -> String

// Already exists but verify:
func searchFoods(query: String) async throws -> FoodSearchResponse
```

## Animation Specifications

| Element | Animation | Duration |
|---------|-----------|----------|
| Calorie ring progress | `.spring(duration: 0.6)` | 0.6s |
| Macro bar fill | `.spring(duration: 0.4)` | 0.4s |
| Portion selector | `.easeInOut(duration: 0.2)` | 0.2s |
| Nutrition banner update | `.numericText()` content transition | default |
| Day card expand | `.spring(duration: 0.3)` | 0.3s |
| Tab glow | static (no animation) | — |
| Meal suggestion load | shimmer skeleton → fade in | 0.3s |

## Accessibility

- All interactive elements: 44pt minimum touch target
- VoiceOver labels on all custom controls (portion selector, provider cards)
- Dynamic Type support: use `.font()` modifiers, not fixed sizes
- Respect system `reduceMotion`: skip glow effects and spring animations
- Color contrast: all text meets WCAG AA on dark backgrounds
- Portion selector: label includes weight ("Medium, approximately 150 grams")

## Meal Suggestion Prompt Template

Reference prompt for the `/api/v1/llm/chat` call (matches the web app's approach):

```
System: You are a nutrition assistant. The user has {remaining_cal} calories remaining today.
Remaining macros: protein {remaining_p}g, carbs {remaining_c}g, fat {remaining_f}g.
Current time: {device_local_time}. Remaining meal slots: {slots}.
Recently eaten: {recent_meals_list}.
User preference: {craving_input or "healthy balanced meals"}.

Suggest 2 options per remaining meal slot. Return ONLY a JSON array:
[{"meal":"dinner","option":1,"food":"...","ingredients":"...","reason":"...","calories":500,"protein_g":35,"carbs_g":50,"fat_g":15}, ...]

Calorie budget per slot: {budget_breakdown}.
Do not repeat foods from recently eaten list.
```

## Testing Plan

**Visual verification:**
- Run in simulator (iPhone 15 Pro) with dark mode
- All 5 tabs load and display themed correctly
- Screenshot each screen for review

**Functional tests:**
- Portion selector: tap S/M/L/XL, verify calorie recalculation in banner
- Portion selector: verify total calories/macros use scaled values (not raw)
- Meal suggestions: mock LLM response, verify card rendering and error states
- Quick food search: search, add item, verify it appears in scan results with correct mapping
- Settings: select each provider, verify config section appears/hides
- Settings: Google/Anthropic show "coming soon" note
- Pull-to-refresh on Dashboard and History
- VoiceOver navigation through all screens
- Dynamic Type: test with largest accessibility text size

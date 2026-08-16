# Unified Log + Grocery Architecture

## Goal

Combine the current `Scan` and `Log` experiences into one clearer `Log` surface that supports:

- meal photo scanning
- barcode scanning for packaged foods
- database search with live matches
- AI-assisted natural-language lookup
- voice-first quick add
- conversion of saved meals into a smarter grocery workflow

The main product principle is: **many ways in, one meal draft underneath**.

## Recommended IA

- Keep tabs focused on:
  - Home
  - Log
  - History
  - Settings
- Move grocery access to:
  - Home shortcut
  - meal save success state
  - meal plan / grocery suggestions surfaces

## UX Recommendation

### 1. Replace `Scan` + `Log` with a single `Log` tab

Top-level modes:

- Scan
- Search
- Ask AI

These should not feel like separate app sections. They are entry points into one intake workflow.

Important nuance:

- `Scan` contains both meal photo capture and barcode scanning
- `Search` preserves the current fuzzy DB search behavior
- `Ask AI` preserves the current AI food lookup behavior

### 2. Use one shared `MealDraftStore`

Everything adds to the same in-progress draft:

- camera analysis results
- barcode lookup results
- database matches
- custom foods
- AI-generated food estimates

This reduces mental load and lets users mix methods in one meal without switching tabs.

### 3. Unify text and voice input

Voice should not become a separate destination. It should fill the same quick-add composer used for typing.

Ideal quick-add pattern:

- user taps into a compact composer sheet
- types or speaks
- live structured matches show below
- the existing AI path remains separate and easy to reach when the user wants a pure macro estimate

### 4. Make camera do both jobs

The camera session should support:

- live barcode detection
- meal photo capture

Suggested modes:

- Photo + barcode
- Barcode first
- Photo first

This is friendlier than making users choose camera vs barcode before opening the camera.

## Preserve current working behavior

### Current search behavior to keep

Today the app already has the right basic search split:

- in cloud mode, `NutritionDB.search(...)` does local token-based fuzzy-ish matching with abbreviation expansion
- in backend mode, `APIClient.searchFoods(...)` calls the existing `/foods` search endpoint

The redesign should mainly change presentation:

- one better composer
- faster-feeling live list
- clearer voice entry

It should not replace the current search pipeline unless there is a measured quality problem.

### Current AI lookup behavior to keep

Today `AIFoodLookupSheet` already works well:

- user enters a natural-language food query
- cloud mode uses `FoodAnalysisService.shared.chatCompletion(...)`
- backend mode uses `APIClient.aiLookup(...)`
- response is parsed into `AIFoodResult`
- result is added as a `FoodItem`

This should remain the macro-estimation engine.

Recommended change:

- add voice-first input
- optionally normalize the raw transcript into a cleaner food-only query before invoking the same existing AI lookup flow

### Current grocery suggestion behavior to keep

Today `GroceryListView.generateList()` already creates AI grocery suggestions from:

- calorie goal
- cuisine / preference input
- a structured LLM prompt returning `GroceryAISuggestion[]`

That should stay in the product.

The redesign should enhance it with:

- better visual grouping
- clearer add-to-cart behavior
- retailer comparison and bucket assignment
- export flows per selected retailer bucket

## Technical Architecture

### Core components

#### `MealDraftStore`

Single source of truth for the in-progress meal.

Responsibilities:

- current meal items
- draft totals
- meal name
- item provenance (`camera`, `barcode`, `db`, `ai`, `custom`)
- save/clear actions

#### `UnifiedLogCoordinator`

UI orchestration layer for the Log tab.

Responsibilities:

- current intake mode
- presentation of camera / composer / barcode result flows
- routing output into `MealDraftStore`

#### `SearchOrchestrator`

Fan-out search service for quick add.

Search priority:

1. recent foods
2. custom foods
3. local nutrition DB
4. server/API DB
5. explicit AI handoff row

Responsibilities:

- debounce user input
- merge/rank heterogeneous results
- expose confidence and source labels

#### `SmartCameraCoordinator`

Camera flow abstraction.

Responsibilities:

- launch one camera session
- barcode recognition
- photo capture
- inline product preview if barcode found
- handoff to image analysis pipeline when shutter is used

#### `VoiceQueryNormalizer`

Optional pre-processing layer for voice-first entry.

Responsibilities:

- accept raw speech transcription
- strip conversational filler
- keep quantities, units, and food nouns
- hand a clean query into either DB search or the existing AI lookup

#### `GroceryPlanner`

Turns meals and plans into normalized grocery demand.

Responsibilities:

- aggregate ingredients and packaged items
- normalize duplicates
- attach estimated quantity needs
- preserve meal/source traceability

#### `RetailerAdapter`

Stable interface around store-specific behavior.

Example responsibilities:

- product search
- price quote fetch
- bucket export target generation
- capability flags per retailer

Suggested protocol shape:

- `searchItems(query:)`
- `quotePrices(for:)`
- `buildExportPayload(for:)`
- `openListURL(for:)`
- `capabilities`

#### `VendorMatchCache`

Persistent cache for vendor lookup results.

Responsibilities:

- normalized grocery item key
- candidate retailer products per item
- latest known unit price and pack size
- match confidence
- last refresh timestamp
- stale/fresh status for UI

#### `StoreBucketStore`

Persistent record of the user's selected retailer per grocery item.

Responsibilities:

- remember which store bucket each item was assigned to
- keep assignments across app relaunches
- allow mixed-store grocery plans
- feed export actions per retailer bucket

#### `PriceRefreshScheduler`

Background refresh policy for vendor data.

Responsibilities:

- trigger lookup work when grocery items change
- refresh stale matches on app open or manual refresh
- avoid duplicate vendor fetches for unchanged items
- update UI incrementally as vendor results arrive

### Retailer bucket behavior

The compare view should do more than show prices.

Recommended interaction:

- user taps a store price for an item
- that item becomes assigned to that retailer bucket
- export actions are bucket-specific

Example:

- yogurt assigned to retailer A
- spinach assigned to retailer B
- bars assigned to retailer C

Then:

- `Export retailer A` only exports the A-assigned items
- `Export retailer B` only exports the B-assigned items
- full checklist remains available as a store-agnostic backup

### Background vendor lookup flow

Recommended lifecycle:

1. grocery item is created or updated
2. normalize it into a stable lookup key
3. schedule background retailer search jobs
4. persist candidate matches and prices into `VendorMatchCache`
5. surface best-known prices immediately
6. let the user tap a price to assign the store bucket
7. persist that choice in `StoreBucketStore`

This keeps the grocery screen responsive and lets vendor intelligence improve over time instead of starting from zero every visit.

## Grocery Strategy

### Phase 1

Ship the useful version first:

- smart grocery list from meals + plans
- local editing and checking off
- price comparison for supported stores
- bucket assignment by tapped store price
- persistent vendor matches and freshness metadata
- export/share/open-in-store-app flows

### Phase 2

Add retailer-specific adapters where stable support exists:

- store-specific search normalization
- retailer-aware substitutions
- store preference memory

### Phase 3

Only after verification:

- direct cart handoff
- auto-fill retailer lists
- purchase-ready bundles

## Why not promise direct retailer checkout first

Based on a quick official-source scan on April 8, 2026:

- Whole Foods exposes shopping lists in the Whole Foods app and Amazon app, and supports Alexa voice additions.
- Target clearly supports shopping lists, barcode scanning in-app, and store-mode shopping flows.
- Safeway exposes `My List`, picture-to-list, and an in-app AI shopping assistant.
- Sprouts clearly promotes app-based shopping lists and ordering, with list workflows also appearing through its Instacart experience.

But I did **not** find equally clear public developer-grade cart/list APIs across all target retailers in the same pass.

That means the safest architecture is:

- UI and data model assume retailer integrations will vary
- app ships with export + compare + open flows first
- direct write integrations sit behind adapters and capability flags

## Suggested implementation order

1. Introduce `MealDraftStore`
2. Build new `LogView` shell or `UnifiedLogView` shell with three entry cards
3. Move current `AnalyzeView` and `LogView` actions behind the new shell
4. Keep the existing DB search and AI lookup engines, but surface them more clearly
5. Add speech-to-text entry
6. Add optional transcript normalization before AI lookup
7. Merge camera and barcode entry under one coordinator
8. Preserve and elevate current grocery AI suggestions
9. Add persistent `VendorMatchCache` and `StoreBucketStore`
10. Add compare/export retailer bucket layer

## Current files most likely to change

- `ios/NutriVisionAI/Views/ContentView.swift`
- `ios/NutriVisionAI/Views/AnalyzeView.swift`
- `ios/NutriVisionAI/Views/LogView.swift`
- `ios/NutriVisionAI/Views/GroceryListView.swift`
- `ios/NutriVisionAI/Services/FoodAnalysisService.swift`
- `ios/NutriVisionAI/Services/LocalMealStore.swift`

Potential new files:

- `ios/NutriVisionAI/Views/UnifiedLogView.swift`
- `ios/NutriVisionAI/Views/QuickAddComposerSheet.swift`
- `ios/NutriVisionAI/Services/MealDraftStore.swift`
- `ios/NutriVisionAI/Services/SearchOrchestrator.swift`
- `ios/NutriVisionAI/Services/SmartCameraCoordinator.swift`
- `ios/NutriVisionAI/Services/VoiceQueryNormalizer.swift`
- `ios/NutriVisionAI/Services/GroceryPlanner.swift`
- `ios/NutriVisionAI/Services/VendorMatchCache.swift`
- `ios/NutriVisionAI/Services/StoreBucketStore.swift`
- `ios/NutriVisionAI/Services/PriceRefreshScheduler.swift`
- `ios/NutriVisionAI/Services/RetailerAdapters/`

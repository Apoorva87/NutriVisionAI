# NutriSight Architecture

## Overview

NutriSight is a local-first FastAPI web app for photo-based nutrition logging. The system is designed around a modular pipeline:

1. Phone or browser uploads a meal image.
2. The server stores the image locally.
3. A vision-capable provider detects likely foods in the image.
4. A portion estimator assigns weights or size labels.
5. Detected foods are normalized into the local nutrition catalog.
6. Nutrition totals are computed from the local SQLite database.
7. The user reviews, edits, and saves the meal.
8. Daily summaries and longer-term trends are read back from SQLite.

The app currently uses LM Studio for live multimodal analysis and SQLite for all local persistence.

## High-Level Components

### Web App

- FastAPI app entrypoint: [app/main.py](/Users/akarnik/experiments/NutriVisionAI/app/main.py)
- Server-rendered templates:
  - [app/templates/index.html](/Users/akarnik/experiments/NutriVisionAI/app/templates/index.html)
  - [app/templates/history.html](/Users/akarnik/experiments/NutriVisionAI/app/templates/history.html)
  - [app/templates/admin_db.html](/Users/akarnik/experiments/NutriVisionAI/app/templates/admin_db.html)
- Frontend behavior and mobile UX:
  - [app/static/app.js](/Users/akarnik/experiments/NutriVisionAI/app/static/app.js)
  - [app/static/styles.css](/Users/akarnik/experiments/NutriVisionAI/app/static/styles.css)

### Analysis Pipeline

- Runtime orchestration: [app/services.py](/Users/akarnik/experiments/NutriVisionAI/app/services.py)
- Schema contracts: [app/schemas.py](/Users/akarnik/experiments/NutriVisionAI/app/schemas.py)
- Provider abstractions:
  - vision: [app/providers/vision.py](/Users/akarnik/experiments/NutriVisionAI/app/providers/vision.py)
  - portion / llm: [app/providers/llm.py](/Users/akarnik/experiments/NutriVisionAI/app/providers/llm.py)
  - nutrition normalization/math: [app/providers/nutrition.py](/Users/akarnik/experiments/NutriVisionAI/app/providers/nutrition.py)

### Data Layer

- SQLite access and catalog import logic: [app/db.py](/Users/akarnik/experiments/NutriVisionAI/app/db.py)
- Seed catalog: [data/nutrition_seed.json](/Users/akarnik/experiments/NutriVisionAI/data/nutrition_seed.json)
- Local source bootstrap: [scripts/bootstrap_nutrition_sources.py](/Users/akarnik/experiments/NutriVisionAI/scripts/bootstrap_nutrition_sources.py)
- Catalog importer: [scripts/import_local_catalog.py](/Users/akarnik/experiments/NutriVisionAI/scripts/import_local_catalog.py)
- Uploaded meal images: `uploads/`

## Current Route Structure

### User-Facing

- `GET /`
  - Main logger UI
  - Displays current-day dashboard, meal review UI, custom foods, auth/session status, and recent meals
- `GET /history`
  - User-specific trends and grouped meal history
- `POST /auth/session`
  - Email-based sign-in / registration and persistent cookie session
- `POST /auth/logout`
  - Clears the device session cookie
- `POST /api/analyze`
  - Upload image and run analysis pipeline
- `POST /api/meals`
  - Save reviewed meal to SQLite
- `GET /api/meals/{meal_id}`
  - Fetch stored meal detail
- `GET /api/foods`
  - Search the nutrition catalog for mobile typeahead and food mapping
- `POST /api/settings`
  - Update goals and provider settings
- `POST /custom-foods`
  - Create a user-owned custom food
- `POST /custom-foods/{custom_food_id}/log`
  - Log a custom food directly as a meal without an image
- `POST /custom-foods/{custom_food_id}/delete`
  - Remove a user-owned custom food

### Admin / Master Data

- `GET /admin/db`
  - Server-rendered DB portal for nutrition catalog management
- `GET /admin/users`
  - Server-rendered admin view of registered users and history counts
- `POST /admin/nutrition-items`
  - Create or update a nutrition item
- `POST /admin/nutrition-items/{item_id}/delete`
  - Remove a nutrition item
- `POST /admin/label-import`
  - Parse a nutrition label image and save the result into the global catalog or a user custom-food list

## Database Structure

### Settings

- `settings`
  - stores provider selection, calorie goal, macro goals, current user name, and LM Studio config

### Users and Sessions

- `users`
  - stores registered name/email identities
- `user_sessions`
  - stores persistent same-device sign-in tokens

### User-Owned Foods

- `custom_foods`
  - per-user foods for quick manual logging or nutrition-label imports

### Nutrition Catalog

- `nutrition_items`
  - canonical foods used for lookup and macro math
- `nutrition_sources`
  - source catalogs such as USDA or Indian composition tables
- `nutrition_source_items`
  - source-specific item rows mapped into canonical foods
- `nutrition_aliases`
  - normalization aliases used to map detected labels into canonical foods

### Meal Logging

- `meals`
  - user-scoped saved meal summaries
- `meal_items`
  - per-item saved details for each meal

## Request Flow

### Analyze Flow

1. Browser selects or captures image.
2. Frontend compresses image when browser APIs allow it.
3. `POST /api/analyze` stores the upload locally.
4. `run_analysis(...)` in [app/services.py](/Users/akarnik/experiments/NutriVisionAI/app/services.py):
   - builds the provider bundle from saved settings
   - calls the vision provider
   - normalizes food names
   - deduplicates overlapping canonical detections
   - calls the portion estimator
   - computes nutrition against SQLite catalog data
5. JSON response is rendered into editable item cards.

### Save Flow

1. User edits names, mapped foods, and grams in the main UI.
2. Frontend recomputes visible totals immediately.
3. `POST /api/meals` validates and normalizes submitted items.
4. Nutrition totals are recomputed server-side from canonical DB values.
5. Meal and meal_items are inserted into SQLite.
6. Current-day dashboard is recalculated and returned.

## Code Structure

### `app/main.py`

- Route handlers
- page composition
- request validation boundaries
- dashboard shaping
- user/session resolution
- custom-food and admin label-import flows

### `app/services.py`

- provider bundle selection
- LM Studio client implementation
- analysis orchestration
- duplicate suppression and fallback portion heuristics

### `app/providers/nutrition.py`

- canonical normalization
- alias and source-label lookup
- macro scaling calculations

### `app/db.py`

- schema creation and migration-safe setup
- settings persistence
- nutrition catalog import and CRUD
- meal persistence and trend queries

### `app/static/app.js`

- image compression
- analysis form submission
- editable meal item UI
- in-card food search and mobile typeahead against `/api/foods`
- client-side totals
- meal history interactions

## Current Architectural Boundaries

- Vision and portion estimation are provider-driven and replaceable.
- Nutrition math is intentionally local and independent of the model provider.
- The DB portal edits the master nutrition catalog directly in SQLite.
- Historical meals remain user-scoped and are not recomputed automatically when catalog rows change.
- Raw USDA and IFCT source artifacts are treated as local-only build inputs under `data/imports/`, not as Git-tracked application assets.

## Known Gaps

- No authentication on admin routes yet.
- No bulk import UI yet for nutrition sources.
- No recipe decomposition layer yet for mixed foods beyond coarse canonical mappings.
- No background jobs or queueing; all analysis runs inline with the request.

## Recommended Next Steps

1. Keep expanding the bootstrap/import flow with richer Indian-source ingestion beyond the IFCT PDF.
2. Extend the admin portal to manage aliases and source rows.
3. Keep refining the model prompts and heuristics on a benchmark set of real meals.

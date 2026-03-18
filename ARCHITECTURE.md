# NutriSight Architecture

## Overview

NutriSight is a local-first FastAPI web app for photo-based nutrition logging. The system is designed around a modular pipeline with a mobile-first multi-page UI:

1. User captures a meal photo or manually searches foods.
2. The server stores the image and runs AI analysis via LM Studio.
3. Detected foods are normalized against the local nutrition catalog.
4. The user reviews, edits macros, and saves the meal.
5. Daily summaries, trends, and AI meal recommendations are computed.

## High-Level Components

### Web App (Multi-Page, Mobile-First)

- FastAPI entrypoint: `app/main.py`
- Shared base template with bottom tab bar: `app/templates/base.html`
- Page templates:
  - `app/templates/dashboard.html` — Home page with daily summary, AI recommendations, recent meals
  - `app/templates/analyze.html` — Photo capture and AI analysis review
  - `app/templates/log.html` — Manual food search, meal builder, favorites
  - `app/templates/history_new.html` — Day-grouped meal history with edit/delete
  - `app/templates/settings.html` — Goals, AI provider config, account
  - `app/templates/admin_db.html` — Nutrition catalog admin
  - `app/templates/admin_users.html` — User admin
- Per-page JavaScript modules:
  - `app/static/shared.js` — Common utilities (escapeHtml, safeNumber, calcNutrition, searchFoods, showToast, compressImage)
  - `app/static/analyze.js` — Image capture, analysis flow, item card rendering, macro edit modal
  - `app/static/log.js` — Food search, meal builder, favorites management
- Styles: `app/static/styles.css` — Mobile-first CSS with bottom tab bar, stepper controls, toggle groups

### Analysis Pipeline

- Runtime orchestration: `app/services.py`
- Schema contracts: `app/schemas.py`
- Provider abstractions:
  - Vision: `app/providers/vision.py`
  - Portion / LLM: `app/providers/llm.py`
  - Nutrition normalization/math: `app/providers/nutrition.py`
- LM Studio client with `chat_json()` (vision) and `chat_text()` (text-only) methods
- Balanced JSON brace parser for robust LLM output extraction

### Data Layer

- SQLite access and catalog import: `app/db.py`
- Seed catalog: `data/nutrition_seed.json`
- Bootstrap scripts: `scripts/bootstrap_nutrition_sources.py`, `scripts/import_local_catalog.py`

## Route Structure

### Pages
- `GET /` — Dashboard (home)
- `GET /analyze` — Scan meal
- `GET /log` — Quick log
- `GET /history` — Meal history
- `GET /settings` — Settings
- `GET /admin/db` — Nutrition catalog admin
- `GET /admin/users` — User admin

### API Endpoints
- `POST /api/analyze` — Upload image, run analysis pipeline
- `POST /api/meals` — Save reviewed meal
- `GET /api/meals/{id}` — Fetch meal detail
- `PUT /api/meals/{id}` — Update saved meal (name, items, macros)
- `DELETE /api/meals/{id}` — Delete a meal
- `GET /api/foods` — Search nutrition catalog
- `POST /api/settings` — Update goals and provider settings
- `POST /api/llm/chat` — Proxy requests to LM Studio (avoids browser CORS)

### Auth
- `POST /auth/session` — Email-based sign-in/registration
- `POST /auth/logout` — Clear session

### Custom Foods
- `POST /custom-foods` — Create user-owned food
- `POST /custom-foods/{id}/log` — Log custom food as meal
- `POST /custom-foods/{id}/delete` — Delete custom food

### Admin
- `POST /admin/nutrition-items` — Create/update nutrition item
- `POST /admin/nutrition-items/{id}/delete` — Delete nutrition item
- `POST /admin/label-import` — Import from nutrition label image

## Database Structure

### Settings
- `settings` — Provider selection, calorie goal, macro goals, LM Studio config

### Users and Sessions
- `users` — Registered identities
- `user_sessions` — Persistent device session tokens

### User-Owned Foods
- `custom_foods` — Per-user foods for quick logging

### Nutrition Catalog
- `nutrition_items` — 7,849 canonical foods (USDA + IFCT)
- `nutrition_sources` — Source catalogs
- `nutrition_source_items` — Source-specific items
- `nutrition_aliases` — Normalization aliases

### Meal Logging
- `meals` — User-scoped meal summaries with totals
- `meal_items` — Per-item details (name, grams, calories, macros)

## Key Architectural Decisions

### Multi-Page vs SPA
The app uses server-rendered Jinja2 templates with per-page vanilla JS modules instead of a SPA framework. This keeps the stack simple, avoids build tooling, and works well for the mobile-first use case.

### AI Recommendations
Meal recommendations call LM Studio directly from the browser via a server-side proxy (`/api/llm/chat`) to avoid CORS. The prompt is constructed client-side with full nutrition context (remaining calories, macros, time of day, eaten foods). Default cuisine is Indian vegetarian. The calorie budget is dynamically allocated across remaining meal slots using proportional weights (breakfast 20%, lunch 35%, snack 10%, dinner 35%), and users can adjust the total budget with ±100 kcal controls before refreshing. Hovering a recommendation card previews the impact on remaining macro budgets.

### Macro Edit Override
Users can override auto-calculated macros on analyzed items. Overrides are stored in card `dataset` attributes and persist through the save flow, giving users full control over nutritional accuracy.

### Client-Server Nutrition Sync
Analysis responses include per-serving nutrition data from the DB so the client can calculate macros accurately without extra round-trips.

## GitHub Pages Preview

Static previews of all pages are rendered by `scripts/render_template_previews.py` and deployed via `.github/workflows/pages.yml`.

## Known Gaps

- No authentication on admin routes
- No recipe decomposition for mixed/composite foods
- No background jobs; all analysis runs inline
- Ollama and API fallback backends are stubbed

# NutriSight

NutriSight is a local-first FastAPI web app for photo-based nutrition logging with a mobile-first multi-page UI. It supports:

- scan a meal photo and get AI-detected food items with editable macros
- manually log foods via search against a 7,800+ item nutrition database
- save favorite foods for one-tap re-logging
- review and edit meals after saving (update items, macros, delete)
- daily dashboard with calorie and macro tracking
- AI-powered meal recommendations for the rest of the day (Indian vegetarian default)
- full meal history with trends, grouped by day
- per-user accounts with persistent device sessions
- configurable AI provider (LM Studio, Ollama, API, or stub)

## Pages

The app is organized into focused mobile-first pages with a bottom tab bar:

| Page | Path | Purpose |
|------|------|---------|
| Dashboard | `/` | Today's calories/macros, AI meal suggestions, recent meals with delete |
| Scan | `/analyze` | Photo capture, AI analysis, review items with editable macros |
| Quick Log | `/log` | Search foods, build meals manually, manage favorites |
| History | `/history` | Day-grouped meal history, edit/delete saved meals |
| Settings | `/settings` | Goals, AI provider config, account management |
| Admin DB | `/admin/db` | Nutrition catalog search/create/update/delete |
| Admin Users | `/admin/users` | User management |

## Stack

- FastAPI + Jinja2 server-rendered templates
- Vanilla JavaScript with per-page modules (`shared.js`, `analyze.js`, `log.js`)
- SQLite for meals, nutrition catalog, users, and settings
- LM Studio integration (OpenAI-compatible API) for vision detection and portion estimation
- Direct LM Studio calls from browser for meal recommendations (proxied through `/api/llm/chat` to avoid CORS)

## Run

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Then open `http://localhost:8000` from your laptop or `http://<your-lan-ip>:8000` from your phone on the same network.

## Test

```bash
pytest tests/ -v
```

Current test coverage includes nutrition math, daily aggregation, endpoint save validation, user-scoped trend helpers, and LM Studio payload parsing.

## Key Features

### Meal Analysis (Scan Page)
- Camera capture with client-side image compression
- AI detection via LM Studio with Qwen3-VL
- Item cards show all macros (P/C/F) and calories
- Tap macros to edit via popup; changes override auto-calculated values
- S/M/L portion toggle + grams stepper
- Change food mapping via full-text search
- Undo on item removal

### AI Meal Recommendations (Dashboard)
- Calls LM Studio directly to suggest meals for remaining meal slots
- Accounts for remaining calories, protein, carbs, and fat
- Time-aware: breakfast (8am), lunch (12pm), snack (4pm), dinner (7pm)
- 2 options per meal slot with ingredient weights
- Dynamic per-meal calorie allocation that sums to the full budget
- Adjustable calorie budget with −/+ buttons (100 kcal steps)
- Indian vegetarian by default; override with keyword input
- Refresh button to regenerate suggestions
- Hidden after 9pm (no meals suggested)

### Meal History (History Page)
- 14-day bar chart and day-grouped meal list
- Tap to expand meal detail with per-item macros
- Edit button: inline editing of meal name, grams, calories, and all macros per item
- Delete items or entire meals
- Top logged foods section

### Dashboard
- Dark card with today's calorie/macro summary and remaining budgets (protein, carbs, fat)
- Hover/touch on recommendation cards previews how remaining budgets would change
- Quick action buttons (Scan, Quick Log)
- Recent meals with inline delete
- AI meal plan section with adjustable calorie budget

## API Endpoints

### User-Facing
- `GET /` — Dashboard
- `GET /analyze` — Scan meal page
- `GET /log` — Quick log page
- `GET /history` — Meal history page
- `GET /settings` — Settings page
- `POST /api/analyze` — Upload image and run analysis
- `POST /api/meals` — Save a meal
- `GET /api/meals/{id}` — Fetch meal detail
- `PUT /api/meals/{id}` — Update a saved meal (name, items, macros)
- `DELETE /api/meals/{id}` — Delete a meal
- `GET /api/foods` — Search nutrition catalog
- `POST /api/settings` — Update goals and provider config
- `POST /api/llm/chat` — Proxy chat requests to LM Studio
- `POST /custom-foods` — Create a user-owned custom food
- `POST /custom-foods/{id}/log` — Log a custom food as a meal
- `POST /custom-foods/{id}/delete` — Delete a custom food

### Admin
- `GET /admin/db` — Nutrition catalog management
- `GET /admin/users` — User management
- `POST /admin/nutrition-items` — Create/update nutrition item
- `POST /admin/nutrition-items/{id}/delete` — Delete nutrition item
- `POST /admin/label-import` — Import from nutrition label image

## GitHub Pages Preview

Static rendered previews of all pages with sample data:

- [https://apoorva87.github.io/NutriVisionAI/](https://apoorva87.github.io/NutriVisionAI/)

What the preview is:
- static rendered preview of the real templates with sample data
- useful for checking layout and mobile presentation

What the preview is not:
- not the live FastAPI app; forms, uploads, and API calls do not work

How to enable:
1. Go to repo `Settings` → `Pages`
2. Set `Source` to `GitHub Actions`
3. Push to `main` or manually run the `Deploy Template Preview` workflow

Files:
- Workflow: `.github/workflows/pages.yml`
- Renderer: `scripts/render_template_previews.py`
- Output: `site/`

## LM Studio Setup

1. Start LM Studio on your machine (default: `http://localhost:1234`)
2. Load a vision-language model (e.g., `qwen/qwen3-vl-8b`)
3. In NutriSight Settings, choose `lmstudio` as provider and configure the URL and model
4. Save settings, then scan a meal

## Project Docs

- `ARCHITECTURE.md` — Runtime flow, route structure, DB schema, code layout
- `SIGNON.md` — Auth options and deployment guidance
- `TODO.md` — Current backlog
- `docs/EXECUTION_LOG.md` — Session-by-session handoff log
- `docs/ROADMAP.md` — Implementation sequence

## Nutrition Catalog

The local catalog stores 7,849 items from USDA Foundation, USDA SR Legacy, and Indian (IFCT) sources. Bootstrap from scratch:

```bash
.venv/bin/python scripts/bootstrap_nutrition_sources.py --download --extract --verify
.venv/bin/python scripts/import_local_catalog.py
```

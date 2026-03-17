# NutriSight

NutriSight is a local-first FastAPI web app for photo-based nutrition logging. The current codebase is a working MVP, not just a scaffold. It already supports:

- upload a meal image from desktop or phone browser
- compress images locally in the browser before upload when supported
- run a modular analysis pipeline against LM Studio
- normalize foods against a local nutrition dataset
- estimate portions with uncertainty
- review and edit the results before saving
- store user-specific meals and aggregate daily calories and macros in SQLite
- custom foods, per-user history, and basic admin catalog tooling

The project is being delivered in phases. The continuity log in `docs/EXECUTION_LOG.md` is the handoff record for future Codex sessions, and `docs/ROADMAP.md` tracks the remaining implementation sequence.

Project-maintenance docs:

- `TODO.md` tracks the current backlog
- `ARCHITECTURE.md` explains the runtime and code structure
- `SIGNON.md` explains sign-in options and public deployment tradeoffs
- `docs/EXECUTION_LOG.md` is the session-by-session handoff log

Live static template preview on GitHub Pages:

- `https://apoorva87.github.io/NutriVisionAI/`

## Stack

- FastAPI server
- Jinja templates + vanilla JavaScript
- SQLite for meal and nutrition storage
- LM Studio integration for multimodal analysis
- Provider interfaces for vision and portion estimation

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
python3 -m unittest discover -s tests -v
```

Current test coverage includes nutrition math, daily aggregation, endpoint save validation, user-scoped trend helpers, and LM Studio payload parsing.

## GitHub Pages Preview

The repo includes a GitHub Actions workflow that renders static preview versions of the Jinja templates and publishes them to GitHub Pages.

Pages URL:

- `https://apoorva87.github.io/NutriVisionAI/`

What the preview is:

- a static rendered preview of the real templates
- sample data injected into the same pages used by the app
- useful for checking layout and mobile presentation on GitHub

What the preview is not:

- it is not the live FastAPI app
- forms, uploads, database actions, and API calls do not work on GitHub Pages

How to enable it in GitHub:

1. Open the GitHub repo.
2. Go to `Settings` -> `Pages`.
3. Under `Build and deployment`, set `Source` to `GitHub Actions`.
4. Push to `main` or manually run the `Deploy Template Preview` workflow from the `Actions` tab.
5. Wait for the workflow to finish, then open `https://apoorva87.github.io/NutriVisionAI/`.

How it works in this repo:

- workflow: `.github/workflows/pages.yml`
- renderer: `scripts/render_template_previews.py`
- output directory: `site/`

## What Is Real vs Stubbed

Implemented now:

- image upload and local file storage
- client-side image compression before upload when browser APIs allow it
- live LM Studio analysis path over the OpenAI-compatible API
- food normalization
- nutrition lookup and total calculation
- source-backed nutrition catalog tables with importable source metadata
- structured schemas and provider registry wiring
- user confirmation and editing flow
- settings persistence for goals, provider selection, and portion style
- settings persistence for LM Studio base URL and model identifiers
- meal history with detail retrieval
- meal logging and daily dashboard totals
- user-scoped meal history and a separate trends page at `/history`
- a simple admin DB portal at `/admin/db` for nutrition catalog search/create/update/delete
- email-based user registration/session persistence with same-device sign-in reuse
- per-user custom foods and quick logging without a photo
- admin users page at `/admin/users`
- nutrition-label image import into either the master DB or user custom foods
- logger-side food search endpoint and mobile typeahead against the larger local catalog

The local catalog is now materially populated, not just seeded:

- 7,849 `nutrition_items` rows in the local SQLite DB
- USDA Foundation + USDA SR Legacy imported into the local catalog
- Indian seed rows retained with official ICMR-NIN IFCT source metadata

Still stubbed and ready for replacement:

- Ollama and API fallback backends
- richer production-grade prompt tuning and portion heuristics
- broader Indian-food ingestion beyond the current seed rows and USDA import
- stronger auth for public Internet deployments

## Suggested Next Improvements

1. Add personalized food-search ranking and repeat-last-meal shortcuts.
2. Expand the Indian-food catalog beyond the current seed rows.
3. Add confidence-threshold states and explicit unknown-food review flows.
4. Add stronger auth for any deployment exposed outside a trusted LAN.
5. Keep improving duplicate-item suppression and weight estimation on complex multi-dish plates.

## Nutrition Catalog Import

The local catalog now stores:

- canonical nutrition rows
- source metadata rows
- source-item rows for imported USDA or Indian food records
- alias rows for normalization

The seed file at `data/nutrition_seed.json` uses that structure already. Future source exports should be shaped similarly and passed through `app.db.import_nutrition_catalog(...)`.

The raw USDA and IFCT source files are intentionally not committed to Git because the official USDA payloads exceed GitHub's file-size limits. Recreate the expected local layout with:

```bash
.venv/bin/python scripts/bootstrap_nutrition_sources.py --download --extract --verify
.venv/bin/python scripts/import_local_catalog.py
```

That bootstrap flow recreates the exact paths already expected by the importer:

- `data/imports/usda_foundation_2025_json.zip`
- `data/imports/usda_sr_legacy_json.zip`
- `data/imports/ifct_2017_full_copy.pdf`
- `data/imports/usda_foundation/FoodData_Central_foundation_food_json_2025-12-18.json`
- `data/imports/usda_sr_legacy/FoodData_Central_sr_legacy_food_json_2018-04.json`

## LM Studio Setup

1. Start the LM Studio local server on your machine, usually at `http://127.0.0.1:1234`.
2. Load a vision-language model in LM Studio.
3. In NutriSight settings, choose `lmstudio` as the provider and fill in:
   - `LM Studio base URL`
   - `LM Studio vision model`
   - `LM Studio portion model` (optional; leave blank to reuse the vision model)
4. Save settings, then analyze a meal.

The current LM Studio integration uses the OpenAI-compatible `POST /v1/chat/completions` path with image input.

For your current deployment, the expected base URL is `http://192.168.0.143:1234`.

## Auth and Deployment

The current app supports lightweight email-based local registration and persistent device sessions for trusted LAN use.

If you want Google sign-in or public Internet access, read:

- `SIGNON.md`

Important constraint: Google Sign-In for web requires HTTPS for production web origins and login endpoints. `localhost` is allowed for local development, but bare LAN HTTP URLs such as `http://192.168.x.x:8000` are not a good production target for Google sign-in.

## Continuity Log

When starting a new Codex session, read `docs/EXECUTION_LOG.md` first. It captures the last verified state, the files that changed, and the next recommended implementation phase. Add a new dated entry at the end of each completed pass so later sessions can resume from the exact state they inherit.

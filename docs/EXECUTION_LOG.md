# Execution Log

This file is the continuity log for future Codex sessions. Update it at the end of each implementation pass with concrete file-level changes, verification status, and next steps.

## 2026-03-17 Session 1

### Scope

- cloned the empty repository
- scaffolded a FastAPI-based local-first web app
- implemented a first vertical slice for upload, analysis, correction, save, and daily totals

### Files Added

- `app/config.py`
- `app/db.py`
- `app/main.py`
- `app/providers/vision.py`
- `app/providers/llm.py`
- `app/providers/nutrition.py`
- `app/templates/index.html`
- `app/static/app.js`
- `app/static/styles.css`
- `data/nutrition_seed.json`
- `README.md`
- `requirements.txt`
- `.gitignore`

### Files Updated

- `app/main.py`
- `app/templates/index.html`
- `app/static/app.js`
- `app/static/styles.css`

### What Works

- image upload to local storage
- stub vision detection pipeline
- food normalization against local nutrition rows
- portion estimation with uncertainty via stub estimator
- manual correction flow
- meal persistence in SQLite
- dashboard totals for the current day

### Verification

- `python3 -m py_compile` passed with `PYTHONPYCACHEPREFIX` redirected into the repo

### Known Gaps Against PRD

- no real Ollama or LM Studio adapter yet
- no image compression before upload
- no USDA import pipeline beyond a small seed dataset
- no tests
- no explicit pipeline result schema or provider abstraction registry
- no settings UI for provider / goals / estimation style
- no detailed meal history view

### Next Recommended Phase

1. Add project roadmap, domain schemas, provider registry, and configuration model.
2. Add settings persistence, meal detail retrieval, richer dashboard/log views, and tests.
3. Add Ollama / LM Studio adapters behind the provider interface.

## 2026-03-17 Session 2

### Scope

- added the continuity-log usage guidance and test command to the README
- added automated tests for nutrition scaling, food normalization, and meal persistence behavior
- kept changes outside runtime app files as requested

### Files Added

- `tests/test_nutrition_and_persistence.py`

### Files Updated

- `README.md`
- `docs/EXECUTION_LOG.md`
- `docs/ROADMAP.md`

### Verification

- pending test run in this session

### Next Recommended Phase

1. Add provider registries and structured schemas in the runtime layer.
2. Add model adapters and image compression in a later pass.
3. Expand test coverage to the API endpoints once runtime work is allowed again.

## 2026-03-17 Session 3

### Scope

- implemented a richer frontend for meal history navigation, meal detail inspection, and settings display
- kept the work inside `app/templates/index.html`, `app/static/app.js`, and `app/static/styles.css`
- serialized backend-rendered settings and recent meals into the page for client-side rendering

### Files Updated

- `app/templates/index.html`
- `app/static/app.js`
- `app/static/styles.css`
- `docs/EXECUTION_LOG.md`

### Verification

- `node --check app/static/app.js` passed

### Next Recommended Phase

1. Add backend support for meal item detail payloads so the detail panel can show full item history from stored meals.
2. Add a real settings persistence UI when backend writes are allowed.
3. Hook the detail view to richer meal records once the backend returns them.

## 2026-03-17 Session 4

### Scope

- added runtime schemas and provider registry wiring for configurable analysis backends
- added settings persistence, meal detail retrieval, and provider health checks on the backend
- integrated the frontend with real meal-detail fetches, settings saves, and client-side image compression
- extended tests for settings persistence and meal detail retrieval

### Files Added

- `app/schemas.py`
- `app/services.py`

### Files Updated

- `app/db.py`
- `app/main.py`
- `app/templates/index.html`
- `app/static/app.js`
- `app/static/styles.css`
- `tests/test_nutrition_and_persistence.py`
- `README.md`
- `docs/EXECUTION_LOG.md`
- `docs/ROADMAP.md`

### Verification

- `python3 -m unittest discover -s tests -v`
- `python3 -m py_compile app/config.py app/db.py app/main.py app/schemas.py app/services.py app/providers/vision.py app/providers/llm.py app/providers/nutrition.py`
- `node --check app/static/app.js`

### Remaining Gaps Against PRD

- provider adapters for Ollama, LM Studio, and API fallback still raise placeholder errors
- nutrition data still comes from a small seed dataset rather than a USDA import pipeline
- explainability metadata is not yet persisted per analysis run
- API endpoint tests and browser-level flow tests are still missing

### Next Recommended Phase

1. Implement real Ollama / LM Studio / API provider adapters behind `app/services.py`.
2. Add USDA import tooling and broaden nutrition coverage.
3. Add API endpoint tests for `/api/analyze`, `/api/meals`, `/api/meals/{id}`, and `/api/settings`.

## 2026-03-17 Session 5

### Scope

- implemented a real LM Studio integration path using the OpenAI-compatible chat completions endpoint
- added settings for LM Studio base URL plus vision and portion model identifiers
- updated the analysis pipeline so portion estimation can consume both normalized items and the uploaded image
- added unit coverage for LM Studio settings/bundle parsing helpers, with graceful skips when runtime dependencies are not installed

### Files Updated

- `app/providers/llm.py`
- `app/schemas.py`
- `app/db.py`
- `app/services.py`
- `app/main.py`
- `app/templates/index.html`
- `app/static/app.js`
- `README.md`
- `docs/EXECUTION_LOG.md`
- `docs/ROADMAP.md`
- `tests/test_lmstudio_services.py`

### Verification

- `python3 -m unittest discover -s tests -v` passed with 3 LM Studio tests skipped because `pydantic` is not installed in this bare shell environment
- `python3 -m py_compile app/config.py app/db.py app/main.py app/schemas.py app/services.py app/providers/vision.py app/providers/llm.py app/providers/nutrition.py`
- `node --check app/static/app.js`

### Remaining Gaps Against PRD

- Ollama and API fallback adapters still raise placeholder errors
- LM Studio integration needs live end-to-end validation against a loaded local model
- nutrition data still uses the small seed dataset
- endpoint-level tests are still missing

### Next Recommended Phase

1. Load and validate an LM Studio VLM end to end, then tune prompts and parsing against real meal images.
2. Add API endpoint tests for analysis, meal save, meal detail, and settings update.
3. Implement the USDA import pipeline and broaden food normalization coverage.

## 2026-03-17 Session 6

### Scope

- switched LM Studio defaults to the real LAN host `http://192.168.0.143:1234`
- confirmed the live model list and exact vision model id `qwen/qwen3-vl-8b`
- installed runtime dependencies into `.venv`
- validated that the LM Studio path works with the local server after adapting to its `json_schema` response-format requirement
- hardened LM Studio parsing so the app does not crash on alternate JSON shapes or empty detections

### Files Updated

- `app/db.py`
- `app/schemas.py`
- `app/services.py`
- `app/main.py`
- `app/templates/index.html`
- `app/static/app.js`
- `README.md`
- `docs/EXECUTION_LOG.md`

### Verification

- created `.venv` and installed `requirements.txt`
- queried `GET http://192.168.0.143:1234/v1/models` and confirmed:
  - `qwen/qwen3-vl-8b`
  - `zai-org/glm-4.7-flash`
- live `run_analysis(...)` call against LM Studio completed successfully after parser fixes
- blank test image produced an empty result instead of a crash, which is acceptable for transport validation

### Important Deployment Notes

- LM Studio on this host rejects `response_format={"type":"json_object"}` and accepts `json_schema`
- the app currently assumes the portion model can also accept image input, so using the same Qwen3-VL model for both stages is correct
- GLM remains out of the meal-image pipeline because it is not being used as a vision model

### Next Recommended Phase

1. Run the full app against a real meal photo and tune the prompts using actual outputs from `qwen/qwen3-vl-8b`.
2. Add API endpoint tests now that dependencies are installed.
3. Split text-only post-processing into a secondary model path later if GLM becomes useful for non-vision reasoning.

## 2026-03-17 Session 7

### Scope

- started the app locally with the project virtual environment
- verified the rendered home page over HTTP
- verified settings persistence over the live `/api/settings` endpoint
- confirmed the app is serving with `lmstudio` selected and `qwen/qwen3-vl-8b` configured

### Verification

- `uvicorn app.main:app --host 127.0.0.1 --port 8000`
- `GET http://127.0.0.1:8000/`
- `POST http://127.0.0.1:8000/api/settings`

### Current Runtime State

- local app server is reachable on `http://127.0.0.1:8000`
- LM Studio host is configured as `http://192.168.0.143:1234`
- vision and portion model are both set to `qwen/qwen3-vl-8b`

### Next Recommended Phase

1. Validate the pipeline with one or more real meal photos and tune prompts against actual outputs.
2. Add API endpoint tests for the live analysis and meal-save flow.
3. Improve nutrition coverage with a USDA import pipeline.

## 2026-03-17 Session 8

### Scope

- investigated the portal upload delay using live server logs
- identified the root cause as a stale `uvicorn` process still running the pre-patch LM Studio portion prompt
- restarted the server with the corrected code and re-ran the analysis flow against a real JPG from `~/Downloads`

### Verification

- `POST /api/analyze` on `/Users/akarnik/Downloads/hands-holding-traditional-indian-thali-with-various-dishes-and-flatbread-photo.jpg` returned `200`
- response payload was:
  - one detected/logged item: `rice`
  - estimated grams: `180`
  - calories: `233.5`

### Findings

- the upload path is now working
- Qwen3-VL is under-detecting the thali image and collapsing the scene to a single `rice` item
- the next meaningful task is prompt tuning for multi-dish plates, especially Indian meals with several bowls/components

### Next Recommended Phase

1. Tighten the vision prompt so it extracts multiple components from complex plates rather than a single dominant food.
2. Add a fallback that preserves unmatched raw detections for user correction instead of dropping them.
3. Capture one or two more real meal outputs to tune prompts against actual failure patterns.

## 2026-03-17 Session 9

### Scope

- changed the vision stage to ask for multiple probable items from complex plates
- preserved unmapped detections instead of dropping them during analysis
- surfaced detection probability and mapping status in the editable item cards
- revalidated the real thali image through the live portal/API flow

### Verification

- `POST /api/analyze` on the thali image now returns multiple candidate items instead of only `rice`
- the returned list included:
  - `rice`
  - `dal`
  - `curry`
  - `naan`
  - `lentils`
  - `chutney`
  - `vegetable curry`
  - `cilantro`
  - `yogurt`
  - `dessert`

### Findings

- the human-in-the-loop flow is now materially better because probable items are exposed for manual rename/remap/remove
- the model is now over-inclusive on this image and adds low-value items like `cilantro` and `dessert`
- the next tuning pass should improve precision and reduce garnish / hallucinated side-item detections

### Next Recommended Phase

1. Tighten the detection prompt to exclude garnish and weakly supported side items.
2. Expand nutrition aliases or import more foods so common Indian dishes can map automatically.
3. Add confidence thresholds and sort candidate items by probability in the UI.

## 2026-03-17 Session 10

### Scope

- added endpoint tests for analysis, save validation, and daily aggregation behavior
- added a regression test for LM Studio payload parsing when the model returns string item lists
- updated the README to reflect the new coverage and the remaining trend-reporting gap

### Files Added

- `tests/test_api_endpoints.py`

### Files Updated

- `tests/test_lmstudio_services.py`
- `README.md`
- `docs/EXECUTION_LOG.md`

### Verification

- `python3 -m unittest discover -s tests -v`
- `python3 -m py_compile tests/test_api_endpoints.py tests/test_lmstudio_services.py tests/test_nutrition_and_persistence.py`

### Next Recommended Phase

1. Wire a user-scoped meal history/trends model into the runtime and add tests for the new page/API.
2. Expand endpoint coverage to `/api/meals/{id}` and `/api/settings` once the current save-flow tests settle.
3. Keep tuning the LM Studio vision prompt on real meal photos.

## 2026-03-17 Session 11

### Scope

- added source-backed nutrition catalog scaffolding to the SQLite layer
- introduced `nutrition_sources`, `nutrition_source_items`, and `nutrition_aliases` tables while preserving the existing canonical `nutrition_items` table
- added `app.db.import_nutrition_catalog(...)` so JSON exports can be loaded or refreshed into the local catalog
- updated nutrition normalization to consult DB-backed aliases and source labels
- converted the seed file into a source-aware catalog shape with USDA and Indian source placeholders
- added regression tests for catalog import, alias persistence, and source-item lookup

### Files Updated

- `app/db.py`
- `app/providers/nutrition.py`
- `data/nutrition_seed.json`
- `tests/test_nutrition_and_persistence.py`
- `README.md`
- `docs/ROADMAP.md`
- `docs/EXECUTION_LOG.md`

### Verification

- `python3 -m unittest discover -s tests -v`
- `python3 -m py_compile app/db.py app/providers/nutrition.py tests/test_nutrition_and_persistence.py`

### What This Enables

- source-backed nutrition data can now be imported without changing the meal logging code
- canonical rows stay stable for existing app behavior
- future USDA and Indian source exports have a clear landing format in the local DB

### Next Recommended Phase

1. Populate the catalog with real USDA FoodData Central export rows and a real Indian food composition export.
2. Add a small import script or admin endpoint if you want repeatable refreshes from those exports.
3. Keep refining the mobile correction UX and confidence handling on the analysis screen.

## 2026-03-17 Session 12

### Scope

- improved the phone-first correction flow on the analysis screen
- added explicit camera-friendly upload wording and live-region status updates
- replaced the dense per-item editor with thumb-friendly controls for mapping, portion size, and quick weight presets
- made the save bar sticky and added automatic scrolling so saved dashboard updates are visible on mobile
- hardened client-side total math with safer numeric handling

### Files Updated

- `app/templates/index.html`
- `app/static/app.js`
- `app/static/styles.css`
- `docs/EXECUTION_LOG.md`

### Verification

- `node --check app/static/app.js`
- `.venv/bin/python -m unittest discover -s tests -v`

### Notes

- backend save and aggregation paths remained unchanged
- the current-day dashboard now flashes and scrolls into view after a successful save
- the meal item cards now favor dropdowns/selects over fine-grained manual editing on small screens

### Next Recommended Phase

1. Continue with nutrition catalog quality work using USDA and credible Indian sources.
2. Add a lightweight trends page refinement if you want more actionable history summaries.
3. Test the mobile flow on a real phone and tune spacing or copy where the finger targets still feel cramped.

## 2026-03-17 Session 13

### Scope

- fixed a startup regression in the nutrition catalog migration path for existing SQLite files
- added canonical-name deduplication in the analysis pipeline so duplicate labels like `curry` plus `vegetable curry` do not both survive when they map to the same DB food
- added a regression test for duplicate-canonical analysis results
- revalidated the live LM Studio analyze path after restarting the app server

### Files Updated

- `app/db.py`
- `app/services.py`
- `tests/test_lmstudio_services.py`
- `README.md`
- `docs/EXECUTION_LOG.md`

### Verification

- `.venv/bin/python -m unittest discover -s tests -v`
- `PYTHONPYCACHEPREFIX=.pycache .venv/bin/python -m py_compile app/db.py app/services.py`
- `node --check app/static/app.js`
- live `POST /api/analyze` against the thali image through the running server

### Findings

- the app now starts cleanly against an existing DB after the nutrition catalog schema changes
- live thali analysis dropped from 9 rows / 1489.6 kcal to 8 rows / 1108.6 kcal after duplicate canonical suppression
- the remaining accuracy issue is portion quality and semantic over-detection, not broken save or aggregation plumbing

### Next Recommended Phase

1. Import real USDA FoodData Central and Indian food composition rows into the new local catalog tables.
2. Keep tuning prompts and heuristics for Indian thalis, especially to separate true distinct legume dishes from duplicate variants.
3. Test the updated save/edit flow on an actual phone browser and tune the default gram presets based on a few real meals.

## 2026-03-17 Session 14

### Scope

- added persistent project docs for backlog and architecture handoff
- built a simple server-rendered DB portal for the nutrition master catalog
- added backend CRUD helpers for nutrition items and a DB overview summary
- linked the logger and history pages to the new admin portal

### Files Added

- `TODO.md`
- `ARCHITECTURE.md`
- `app/templates/admin_db.html`

### Files Updated

- `app/main.py`
- `app/db.py`
- `app/templates/index.html`
- `app/templates/history.html`
- `app/static/styles.css`
- `README.md`
- `tests/test_api_endpoints.py`
- `tests/test_nutrition_and_persistence.py`
- `docs/EXECUTION_LOG.md`

### Verification

- `.venv/bin/python -m unittest discover -s tests -v`
- `PYTHONPYCACHEPREFIX=.pycache .venv/bin/python -m py_compile app/main.py app/db.py tests/test_api_endpoints.py tests/test_nutrition_and_persistence.py`
- confirmed the main app still renders via local `curl`

### What Was Added

- `TODO.md` now tracks the active backlog
- `ARCHITECTURE.md` now documents the current runtime flow, route structure, DB schema, and code layout
- `/admin/db` shows:
  - nutrition item search
  - add/edit/delete controls for canonical nutrition rows
  - source catalog visibility
  - recent stored meals
  - DB overview counts

### Next Recommended Phase

1. Extend the DB portal to manage aliases and source-item rows directly.
2. Add import/export controls for nutrition catalog JSON or CSV.
3. Add authentication if the app will be reachable beyond a trusted LAN.

## 2026-03-17 Session 15

### Scope

- corrected the Indian source metadata to point at the official ICMR-NIN IFCT PDF instead of the non-official site
- downloaded the official USDA FoodData Central Foundation and SR Legacy JSON archives locally
- added a repeatable import script for bulk local catalog population
- imported the USDA catalogs into the local SQLite DB

### Files Added

- `scripts/import_local_catalog.py`

### Files Updated

- `data/nutrition_seed.json`
- `README.md`
- `TODO.md`
- `docs/EXECUTION_LOG.md`

### Verification

- confirmed both USDA archives and the IFCT PDF downloaded successfully into `data/imports/`
- ran `.venv/bin/python scripts/import_local_catalog.py`
- verified DB counts with `sqlite3 app.db`

### Result

- `nutrition_items`: `7849`
- `nutrition_sources`: `3`
- `nutrition_source_items`: `7906`
- `nutrition_aliases`: `18`

### Notes

- the local DB is now genuinely populated rather than only seeded
- Indian-specific coverage is still thinner than USDA because the official IFCT source is a PDF and has not yet been extracted into structured rows at scale
- common Indian items such as chapati/paratha are now present via USDA imports, and the existing Indian seed pack remains in place

### Next Recommended Phase

1. Extract a broader set of Indian foods from the official IFCT PDF into structured import rows.
2. Add a search API/typeahead for the main meal editor so the large food catalog does not have to be embedded wholesale in the page.
3. Expand the DB portal to manage aliases and source-item rows directly.

## 2026-03-17 Session 16

### Scope

- added lightweight email-based user registration with persistent same-device cookie sessions
- added user-owned custom foods and quick logging without a photo
- added an admin users page with registration and history counts
- added nutrition-label image import routing so labels can be saved into the master DB or into a user's custom-food list
- improved the logger templates for mobile use by moving account and quick-log flows into simple server-rendered forms

### Files Added

- `app/templates/admin_users.html`

### Files Updated

- `app/db.py`
- `app/main.py`
- `app/services.py`
- `app/templates/index.html`
- `app/templates/history.html`
- `app/templates/admin_db.html`
- `app/schemas.py`
- `tests/test_api_endpoints.py`
- `tests/test_nutrition_and_persistence.py`
- `README.md`
- `ARCHITECTURE.md`
- `docs/EXECUTION_LOG.md`

### Verification

- `.venv/bin/python -m unittest discover -s tests -v`
- `PYTHONPYCACHEPREFIX=.pycache .venv/bin/python -m py_compile app/db.py app/main.py app/services.py`
- `node --check app/static/app.js`

### Notes

- same-device sign-in persistence is now cookie-based and stored in SQLite, not localStorage-only
- the nutrition-label import path currently depends on the LM Studio provider being available
- the main logger now uses a smaller food list slice for mobile practicality; a proper search/typeahead API is still the right next step for the large catalog

### Next Recommended Phase

1. Add a nutrition search/typeahead API so the logger can use the full catalog without embedding large lists.
2. Extract more structured Indian foods from the official IFCT PDF into the local DB.
3. Add authentication hardening if the app will be exposed outside a trusted LAN.

## 2026-03-17 Session 17

### Scope

- added a real food search API for the logger
- replaced the logger's static food mapping dependence with mobile-friendly in-card typeahead
- added simple recent-choice memory on the client so repeated mappings get easier over time
- trimmed the logger bootstrap food list to quick choices instead of flooding the page with the full catalog

### Files Updated

- `app/main.py`
- `app/static/app.js`
- `app/static/styles.css`
- `app/templates/index.html`
- `tests/test_api_endpoints.py`
- `README.md`
- `ARCHITECTURE.md`
- `TODO.md`
- `docs/EXECUTION_LOG.md`

### Verification

- `.venv/bin/python -m unittest discover -s tests -v`
- `PYTHONPYCACHEPREFIX=.pycache .venv/bin/python -m py_compile app/main.py tests/test_api_endpoints.py`
- `node --check app/static/app.js`

### Notes

- the main logger can now search the full nutrition DB through `/api/foods`
- mobile food mapping is materially better because users do not need to scroll giant selects
- recent client-side choices now help repeated use from the same device, even before a fuller favorites system exists

### Next Recommended Phase

1. Add ranking that favors the current user's recent and frequent foods in `/api/foods`.
2. Add meal cloning / repeat-last-meal shortcuts for common recurring meals.
3. Continue expanding Indian-food coverage from the official IFCT source.

## 2026-03-17 Session 18

### Scope

- moved raw source datasets out of the intended Git surface by ignoring `data/imports/**`
- added a repeatable bootstrap script that downloads USDA and IFCT artifacts into the exact file layout already expected by the importer
- added a regression test for archive extraction and missing-file guidance
- documented the local-only nutrition data bootstrap flow for fresh clones

### Files Added

- `data/imports/README.md`
- `data/imports/.gitkeep`
- `scripts/bootstrap_nutrition_sources.py`
- `tests/test_bootstrap_sources.py`

### Files Updated

- `.gitignore`
- `scripts/import_local_catalog.py`
- `README.md`
- `TODO.md`
- `ARCHITECTURE.md`
- `docs/EXECUTION_LOG.md`

### Verification

- `.venv/bin/python scripts/bootstrap_nutrition_sources.py --verify`
- `.venv/bin/python -m unittest discover -s tests -v`
- `PYTHONPYCACHEPREFIX=.pycache .venv/bin/python -m py_compile scripts/bootstrap_nutrition_sources.py scripts/import_local_catalog.py`

### Notes

- the bootstrap script uses official source URLs and reconstructs the same filenames and directories already used by the importer
- the large USDA files still exist locally for development, but Git is now configured to ignore them
- the local branch still needs one cleanup pass before push because earlier commits already captured those large artifacts

### Next Recommended Phase

1. Rewrite the local branch tip so the previously committed `data/imports` artifacts are no longer in history, then push.
2. Add personalized food-search ranking and repeat-last-meal shortcuts.
3. Continue expanding Indian-food coverage beyond the current seed rows.

## 2026-03-17 Session 19

### Scope

- refreshed `README.md` so it better reflects the current MVP state instead of describing the app as mostly scaffold-only
- added `SIGNON.md` covering Google sign-in requirements, HTTPS constraints, hosting tradeoffs, and low-cost deployment paths
- updated backlog and architecture notes to make the current auth boundary explicit

### Files Added

- `SIGNON.md`

### Files Updated

- `README.md`
- `TODO.md`
- `ARCHITECTURE.md`
- `docs/EXECUTION_LOG.md`

### Notes

- the current built-in email session flow is still appropriate for trusted LAN use
- Google sign-in should be deferred until the app is reachable on a stable HTTPS hostname
- the recommended low-cost public path remains self-hosting plus Caddy or Cloudflare Tunnel, keeping LM Studio private on the LAN

### Next Recommended Phase

1. Add personalized food-search ranking and repeat-last-meal shortcuts.
2. Add stronger auth and admin protection if the app is going online.
3. Continue expanding Indian-food coverage and prompt quality.

## 2026-03-17 Session 20

### Scope

- added a static template preview renderer for GitHub Pages
- added a GitHub Actions workflow that builds and deploys rendered previews from `main`
- updated the README with the expected Pages URL and the exact GitHub Pages setup steps

### Files Added

- `scripts/render_template_previews.py`
- `.github/workflows/pages.yml`

### Files Updated

- `README.md`
- `ARCHITECTURE.md`
- `TODO.md`
- `docs/EXECUTION_LOG.md`

### Notes

- GitHub Pages can only host static files, so the workflow renders sample-data previews of the Jinja templates instead of publishing the raw templates
- the Pages site is for layout review only; uploads, API calls, and DB actions remain disabled there

### Next Recommended Phase

1. Verify the deployed GitHub Pages preview after the workflow runs.
2. Add personalized food-search ranking and repeat-last-meal shortcuts.
3. Tighten admin protection before any public deployment.

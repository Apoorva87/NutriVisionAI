# NutriVisionAI - Known Issues

Code review performed on 2026-03-17.

## Fixed (2026-03-17)

- [x] **#1 `datetime.utcnow()` deprecated** — Replaced with `datetime.now(timezone.utc)` in `main.py` and `db.py`.
- [x] **#2 Full table scan in fuzzy matching** — `normalize_food_name()` loaded all ~7,800 nutrition items on every call. Added `search_nutrition_names()` (returns only names) and a 60-second in-memory cache.
- [x] **#3 Duplicate JS globals across files** — `app.js` redefined `escapeHtml`, `safeNumber`, `normalizeLabel`, `formatMealDate`, `parseRange`, `compressImage`, `nutritionLookup`, `perGram` that already exist in `shared.js`. Removed duplicates; `app.js` now relies on `shared.js` and seeds fallback data into the shared `nutritionLookup` via `Object.assign`.
- [x] **#4 `app.js` crashes on null elements** — `analyzeForm`, `resultsForm`, `addItemButton` were accessed unconditionally. Added null guards.
- [x] **#6 Separate `nutritionLookup` objects** — `app.js` created its own `nutritionLookup` object, so `analyze.js` and `app.js` wrote to different caches. Fixed by having `app.js` use the shared one.

## Fixed (2026-03-18)

- [x] **#8 LLM proxy is an open relay** — Added auth check (requires signed-in user, rejects system/default user) and payload whitelist (only `model`, `messages`, `temperature` keys forwarded).
- [x] **#9 SQL string formatting in `ensure_column`** — Added table whitelist (`_ALLOWED_TABLES`) and `column.isidentifier()` check to block injection via future callers.
- [x] **#10 Session cookie missing `Secure` flag** — Now set conditionally: `secure=True` when request is HTTPS (detected via scheme or `x-forwarded-proto` header), `secure=False` for local HTTP dev.
- [x] **#11 SQLite concurrency issues** — Enabled WAL mode (`PRAGMA journal_mode=WAL`) and busy timeout (`PRAGMA busy_timeout=5000`) in `get_connection()`. Prevents `database is locked` errors under concurrent requests.
- [x] **#12 `resolve_current_user` can return `None`** — Added in-memory fallback dict when `fetch_user_by_email("default@local.nutrisight")` returns `None` (corrupted DB), so routes never crash.
- [x] **#14 Double `normalize_food_name` calls in `run_analysis`** — Collapsed two calls per candidate item into one by caching the result in a local variable.
- [x] **#16 `on_startup` uses deprecated FastAPI event syntax** — Migrated from `@app.on_event("startup")` to `lifespan` async context manager.
- [x] **#17 No email validation** — Added regex-based email format validation to `AuthPayload` via `@field_validator`. Invalid emails now return a redirect with error message instead of a 500.

## Open — Security

- [ ] **#5 No CSRF protection** — All POST endpoints accept form data without CSRF tokens. `samesite="lax"` helps but doesn't fully protect against cross-origin form POSTs. See `ISSUE_CSRF.md` for detailed analysis and implementation options.
- [ ] **#7 Admin routes have no authentication** — `/admin/db`, `/admin/users`, `/admin/nutrition-items`, `/admin/label-import` are accessible by anyone. Add auth checks (e.g., require an admin session or specific user flag).

## Open — Reliability

- [ ] **#13 Uploaded files never cleaned up** — Images in `uploads/` persist forever, even after meal deletion. Add cleanup on meal delete or a periodic purge.

## Open — Code Quality

- [ ] **#15 `app.js` is 1,100 lines serving multiple pages** — Monolithic file handles dashboard, history, settings, and old analyze flow. Should be split per-page (the newer `analyze.js` and `log.js` already follow the right pattern). Note: `index.html` (the only template loading `app.js`) is a dead template — no route references it.
- [ ] **#18 N+1 query in `fetch_meals_grouped_by_day`** — Fetches trends, then runs a separate query per day (up to 15 queries for 14 days). Refactor to a single query.
- [ ] **#19 `foodSearchCache` never evicts entries** — The JS `Map` grows unbounded. Not critical for typical sessions but consider an LRU or size cap.

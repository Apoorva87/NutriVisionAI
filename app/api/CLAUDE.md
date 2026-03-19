# app/api/ — Versioned JSON API

This is the clean API layer consumed by iOS and future web clients.

## Rules

- All routes are under `/api/v1/` (prefix set in `__init__.py`).
- Every response MUST be JSON. Never return HTML, redirects, or set cookies from these routes (exception: `auth/login` sets a cookie as a convenience for web, but the primary auth mechanism is the Bearer token in the response).
- Use `Depends(get_current_user)` from `deps.py` for auth. This handles both Bearer token and cookie transparently.
- Accept JSON request bodies, not form-encoded data.
- Use Pydantic models from `schemas.py` for validation. These are the API contract.
- Keep routes thin — delegate to `services.py` and `db.py`.

## File layout

- `deps.py` — Auth dependency, session helpers
- `auth.py` — Login/logout/me
- `meals.py` — Meal CRUD
- `analysis.py` — Image upload + AI food detection
- `foods.py` — Nutrition DB search
- `settings.py` — App settings
- `dashboard.py` — Daily summary
- `history.py` — Trends and history
- `custom_foods.py` — User custom foods
- `admin.py` — Admin: nutrition items, users, label import
- `llm.py` — LLM proxy, AI food lookup

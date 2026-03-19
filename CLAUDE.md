# NutriVisionAI

Multi-platform nutrition tracking app with AI food recognition.

## Architecture

```
├── app/            # Python backend (FastAPI)
│   ├── api/        # JSON REST API (v1) — used by iOS and web
│   ├── templates/  # Jinja2 HTML templates (web frontend, legacy routes)
│   ├── static/     # Web JS/CSS
│   ├── providers/  # Vision/LLM/nutrition provider abstractions
│   ├── db.py       # SQLite data layer
│   ├── services.py # Business logic (analysis pipeline, LLM integration)
│   ├── schemas.py  # Pydantic models — THE API CONTRACT
│   └── main.py     # FastAPI app, mounts API router + legacy HTML routes
├── ios/            # Swift iOS app (SwiftUI, targets iOS 17+)
└── site/           # Old static HTML (deprecated, kept for reference)
```

## Two API layers

- **Legacy routes** (`/api/meals`, `/auth/session`, etc.) — used by current web JS. Form-encoded, cookie auth. Do not break these.
- **Versioned API** (`/api/v1/*`) — clean JSON-only, supports Bearer token auth. Used by iOS and new clients.

Both coexist. The v1 API is the canonical one for new development.

## Key conventions

- All API responses are JSON. Never return HTML from `/api/v1/*` routes.
- Auth: Bearer token OR cookie session — see `app/api/deps.py:get_current_user`.
- `schemas.py` is the shared contract. When you change a schema, update the matching Swift struct in `ios/NutriVisionAI/Models/NutritionModels.swift`.
- Database is SQLite with WAL mode. No migrations framework — schema is in `db.py:init_db()`.
- Tests: `pytest` for backend. Run with `.venv/bin/python -m pytest tests/ -v`.

## Running

```bash
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API docs at http://localhost:8000/docs (auto-generated OpenAPI).

# iBuyGrocery — VPS Backend & Web Tool

> **Status — superseded by the implementation spec, 2026-04-18.**
>
> The team chose a tighter, Coolify-shaped execution that defers Postgres,
> Redis, separate worker containers, and FastAPI-side auth UI in favour of
> reusing the existing `apoorvakarnik.top` NextAuth stack. The
> authoritative plan is:
>
> `~/experiments/iBuyGrocery/docs/superpowers/specs/2026-04-18-coolify-deploy-design.md`
>
> Notable deltas from this draft, on the iOS side (already shipped):
>
> - All routes prefixed with `/api/v1` (lockstep cutover, no dual-paths).
> - Auth header: `X-API-Key: sk_search_...` (not `Authorization: Bearer`).
> - Reachability ping uses unauthenticated `GET /api/v1/healthz`.
> - Identity badge in Settings uses `GET /api/v1/auth/me`.
> - Keychain slot name `ibg_api_token` preserved (no migration needed).
>
> This file is kept as historical context for design alternatives the team
> considered (Postgres/Redis topology, in-house auth, etc.) — useful when
> the user count outgrows the simple SQLite + single-container shape.

## Goal

Promote the iBuyGrocery FastAPI+React project from a **single-user localhost tool**
into a **self-hosted web product** on a small VPS, while continuing to serve the
NutriVisionAI iOS app as a first-class client.

Two simultaneous surfaces, one backend:

1. **Web tool** — a complete, self-sufficient web app for list building, price
   discovery, basket planning, and shopping. Served by the same VPS.
2. **API for iOS** — the exact same REST + SSE endpoints the iOS app already
   calls, gated by an API token.

This spec captures the concrete changes needed on top of today's `~/experiments/iBuyGrocery`
codebase.

---

## Current State (2026-04-17)

- FastAPI on `http://localhost:8766`, Uvicorn, single process.
- React/Vite dev server on `http://localhost:5173`.
- SQLite file at `backend/ibuygrocery.db`, schema owned by SQLModel.
- SSE via `sse-starlette` at `/events/list/{list_id}`.
- Providers are Playwright scrapers that open a visible browser on macOS.
- No authentication, no users, no CORS policy beyond "allow all", single
  global `Settings` row in SQLite.
- All provider API keys live in a local `.env` on the developer machine.

## Target State

- Deployed on a single small-to-midsize VPS (2 vCPU / 4 GB RAM is enough to
  start) behind a reverse proxy with TLS.
- Multi-tenant: each user has their own lists, settings, store selections,
  and price history. **Provider scraping is shared** across tenants (results
  are reusable, not private).
- Web tool served from the same origin as the API (no CORS headaches).
- iOS app talks to the same HTTPS endpoint with a per-device API token.
- Playwright runs **headless** in a dedicated worker pool, not in the web
  process.

---

## Architecture

### Processes on the VPS

```
                ┌──────────────────┐
 users ──TLS──► │  Caddy / Nginx   │
                └────────┬─────────┘
                         │ proxy_pass
                         ▼
                ┌──────────────────┐      ┌────────────────────┐
                │  FastAPI (web+   │──────│ Postgres           │
                │  API, uvicorn)   │      │ (users, lists,     │
                │                  │      │  settings, cache)  │
                └────┬─────────┬───┘      └────────────────────┘
                     │ enqueue │ publish
                     ▼         ▼
                ┌──────────────────┐      ┌────────────────────┐
                │  Redis (queue +  │      │  Playwright worker │
                │  pub/sub + SSE   │◄─────│  pool (headless)   │
                │  fan-out)        │      │                    │
                └──────────────────┘      └────────────────────┘
```

Three processes (all systemd units):

- `ibg-web` — FastAPI + StaticFiles for the SPA.
- `ibg-worker` — Python worker that pulls resolve jobs off Redis and drives Playwright.
- `ibg-cron` — periodic jobs (stale-price refresh, cache trimming, metrics).

### Deployment targets

- **Docker Compose** is the canonical form. Single `docker-compose.yml`
  provisioning web, worker, redis, postgres, caddy. This is what ships in
  the repo and what users self-hosting follow.
- **Bare-metal systemd** is documented for the primary instance we run. The
  Compose file is the source of truth for env vars.

### Reverse proxy

- Caddy by default (auto-TLS via Let's Encrypt on the user's domain).
- `Caddyfile`:
  - `/` → web SPA static assets.
  - `/api/*` → FastAPI.
  - `/events/*` → FastAPI with `flush_interval 0` and long timeout for SSE.
- Optional Nginx recipe in `deploy/nginx.conf` for users who already run it.

---

## Auth & Identity

### Users

- New `users` table:
  - `id` (uuid), `email`, `password_hash` (argon2), `display_name`,
    `created_at`, `last_login_at`, `is_admin` bool.
- Self-signup **off by default**, admin-invite on by default. Single-user
  setups just create an admin via CLI (`ibg users create …`).
- Password reset is a signed, time-boxed URL sent via an outbound SMTP the
  operator configures — if SMTP isn't configured, reset falls back to
  admin-only CLI reset.

### Sessions (web)

- HttpOnly, Secure, SameSite=Lax session cookies.
- CSRF via double-submit cookie on state-changing endpoints.

### API tokens (iOS, automations)

- New `api_tokens` table:
  - `id`, `user_id`, `name` (user-visible label, e.g. "iPhone 15"),
    `token_hash` (sha256), `token_prefix` (first 8 chars, for display),
    `created_at`, `last_used_at`, `revoked_at`.
- Tokens look like `ibg_live_<32 urlsafe bytes>`. Shown exactly once at
  creation, never again.
- Sent as `Authorization: Bearer <token>`. Middleware resolves `request.user`
  from either a valid session cookie or a bearer token.
- Rate-limit: 60 req/min per token and 600 req/hour per user (configurable).

### What the iOS app sees

No change to the REST shape. The only new requirement is:
`Authorization: Bearer <token>`. The iOS client already supports this and
already stores the token in Keychain under `ibg_api_token` (see
`ios/NutriVisionAI/Services/IBuyGroceryClient.swift`). The UI already
exposes URL + token fields under Settings → Store Prices.

---

## Data Model Changes

### Multi-tenant scoping

Every user-owned table gets a `user_id` foreign key and a unique/lookup
index including `user_id`:

- `shopping_lists`
- `list_items`
- `settings` (was singleton; becomes one row per user — migrate existing row
  to the bootstrap admin)
- `provider_state` (per-user store selection for providers in `storePicker`
  mode; the enabled/disabled flag is also per-user)

Tables that remain **global / shared**:

- `providers` (catalog) — one row per scraper.
- `products_catalog` / `candidates_cache` — resolved products and offers
  scraped from retailers. Keyed by `(provider_id, external_item_id)`; no
  `user_id`. Multiple users searching "jasmine rice" reuse the same rows.
- `price_history` — `(candidate_id, timestamp, price)` — shared.

### Postgres migration

- Swap SQLModel's SQLite engine for Postgres. The ORM code already uses
  SQLModel, so most models stay; only engine config and a couple of
  column types change (`JSON` → `JSONB`, `DateTime` → `timestamptz`).
- Use **Alembic** for migrations. First migration: build the Postgres
  schema from scratch at the target state. A second migration script
  imports a user's existing `ibuygrocery.db` into their new row in the
  hosted DB (see Migration Plan below).

### Caching behaviour

- Candidate resolution is cached for `PRICE_TTL_MIN` (default 30 min).
- A re-resolve request bypasses the cache only for the requested item(s).
- Cache hits don't trigger Playwright at all — they return immediately and
  still fire an `item_resolved` SSE event so the UI reacts.

---

## API Changes

### Path prefix

All existing endpoints move under `/api/v1/…`. The SSE stream moves to
`/api/v1/events/list/{list_id}`. Rationale: makes the `/` root available
for the SPA and gives us headroom for future versioning.

Old paths (`/lists/today`, `/list-items/…`) are kept as 301 redirects for
two releases so the iOS app keeps working mid-migration. The iOS client
will be updated in lockstep to target `/api/v1`.

### New endpoints

- `POST /api/v1/auth/login` → sets session cookie.
- `POST /api/v1/auth/logout`.
- `GET  /api/v1/auth/me` → `{id, email, display_name, is_admin}`.
- `POST /api/v1/auth/tokens` → mint an API token (returns plaintext once).
- `GET  /api/v1/auth/tokens` → list tokens for the current user.
- `DELETE /api/v1/auth/tokens/{id}` → revoke.
- `GET  /api/v1/healthz` → `{ok:true, version, queue_depth}` — unauthenticated.
- `GET  /api/v1/version` — unauthenticated.

### Unchanged shape

Everything else (`/lists/today`, `/lists/{id}/items`, `/list-items/{id}/candidates`,
`/baskets/{id}`, `/settings`, `/providers`, etc.) keeps the same request and
response schemas. The only addition is that each response is implicitly
scoped to the authenticated user. This means **zero model-level changes on
the iOS client** after the path prefix is updated.

### Errors

- `401` on missing/invalid credentials.
- `403` on valid user but wrong scope (admin endpoints, another user's list).
- `409` on cache races (same list resolving twice).
- `429` on rate-limit hit — `Retry-After` header included.

---

## Provider Scraping on the Server

This is the trickiest bit, because the current Playwright providers are
written for a developer's Mac with a visible browser.

### Worker pool

- Dedicated `ibg-worker` process. Pulls jobs from Redis list `jobs:resolve`.
- Each worker runs N concurrent Playwright contexts (default 2; tunable).
- Playwright runs **headless Chromium** inside the VPS using the Docker
  Playwright image (`mcr.microsoft.com/playwright/python:v1.47.0-jammy`).

### Job flow

1. Web process writes `ListItem` with `state=queued` and enqueues
   `{list_item_id}` to `jobs:resolve`.
2. Worker picks up, iterates enabled providers for that user, opens a
   Playwright context per provider (isolated storageState per provider so
   one user's Target login doesn't leak to another). Scrapes, normalises,
   writes candidates.
3. Worker updates `list_items.state` → `searching` → `recommended` (or
   `needs_review` / `provider_error`) and PUBLISHes `item_resolved` to
   Redis channel `sse:user:{user_id}:list:{list_id}`.
4. SSE endpoint in the web process SUBSCRIBEs to that channel and fans out
   events to connected clients.

### Isolation & resource limits

- Worker container gets a memory limit (`--memory=1.5g`) and a CPU quota.
- Chromium launched with `--disable-dev-shm-usage --no-sandbox` (we run
  inside a container, so this is safe).
- Per-user concurrency cap: default 2 in-flight provider scrapes per user,
  to prevent one user monopolising the pool.
- Global concurrency: default 8. Above that, jobs queue.

### Provider storage state

- Per-provider, per-user `storageState` blob (cookies + localStorage) lives
  in the DB (`provider_state.storage_state_json`). This is what lets a user
  "stay logged in" to Walmart or Safeway between sessions.
- Storage state is encrypted at rest with a key derived from
  `APP_SECRET_KEY`. Rotating the key invalidates all stored sessions (users
  just log in again).

### "Search links only" providers

Instacart and Patel Bros don't return prices — they return search URLs.
These remain fast in-process operations, skip the queue, and don't need a
Playwright context.

---

## Web Tool (SPA)

- The existing React app keeps its structure; three concrete changes:
  - **Login screen** at `/login` that posts to `/api/v1/auth/login`.
  - **Settings → API tokens** page to mint / list / revoke tokens for iOS.
  - **No more hard-coded `http://localhost:8766`**. API calls use
    `import.meta.env.VITE_API_BASE || "/api/v1"`. In production, served
    same-origin; no CORS config needed.
- Build artefacts (`frontend/dist/`) are mounted into the web process via
  `StaticFiles` so the same container serves the SPA.

---

## Secrets & Configuration

- `.env` at the container level (mounted as secret file in production).
- Required:
  - `DATABASE_URL`, `REDIS_URL`
  - `APP_SECRET_KEY` (used for session cookies + provider-state encryption)
  - `ALLOWED_ORIGINS` (optional, for split-origin deploys)
  - `SMTP_*` (optional, enables password reset)
- Per-user provider API keys (where applicable — e.g. if we add a paid
  pricing API later) live in the DB encrypted with `APP_SECRET_KEY`. The
  current Playwright providers don't need any per-user keys.

---

## Observability

- Structured JSON logs to stdout (Caddy captures and ships wherever).
- `/api/v1/healthz` returns queue depth + DB ping latency.
- Prometheus metrics at `/metrics` (unauthenticated, but restricted to a
  private network by Caddy).
  - `ibg_jobs_in_flight`, `ibg_jobs_queued`, `ibg_provider_errors_total{provider}`,
    `ibg_resolve_duration_seconds{provider}`, `ibg_sse_connections`.
- Per-request structured log entry with `user_id`, `route`, `status`, `ms`.

---

## Rate-limits & Abuse

- IP-level limits at Caddy (tight) for `/api/v1/auth/login` to slow
  credential stuffing.
- Token-level limit at FastAPI middleware (60/min, 600/hour default).
- Per-user scrape budget: default 200 candidate-resolution operations per
  day. Configurable globally and per-user.

---

## Migration Plan

We migrate the existing local dev tool to a hosted deployment in phases
without breaking the current iOS wiring.

### Phase 0 — Ship iOS VPS toggle (DONE, 2026-04-17)

- iOS `IBuyGroceryClient` reads `baseURL` + bearer token; settings UI
  exposes both. Same binary works against localhost (no token) and
  eventually against the hosted backend (token required).

### Phase 1 — Add auth to the existing backend

- Add `users` and `api_tokens` tables, middleware, and `/auth/*` endpoints.
- Add an `AUTH_MODE` env var: `off` (current behaviour) or `on`. Default
  `off` so local dev keeps working.
- Add `/api/v1` alias mount; keep old paths.

### Phase 2 — Package for deployment

- Write `Dockerfile.web`, `Dockerfile.worker`, `docker-compose.yml`, and
  `Caddyfile`.
- Stand up a dev instance on the chosen VPS host. Point a staging subdomain
  at it.
- Verify: log in from the web, mint a token, point the iOS simulator at
  `https://staging.example.com` with that token, see live SSE updates.

### Phase 3 — Postgres + worker pool

- Add Alembic, switch to Postgres in the compose file.
- Move resolve jobs to Redis queue; split worker into its own process.
- SSE fan-out via Redis pub/sub.
- Load-test with a synthetic 10-item list × 5 providers × 3 users.

### Phase 4 — Web-tool polish

- Login / sessions / token management UI.
- Remove all hard-coded localhost URLs from the SPA.
- SPA served same-origin via StaticFiles.

### Phase 5 — Public beta

- Admin tool: invite-code signup, user admin, provider health dashboard.
- Backup job: daily `pg_dump` to S3-compatible storage.
- Retire the legacy unauth'd `/lists/today`-style paths after the iOS app
  has shipped a build on `/api/v1`.

### Local dev compatibility throughout

- `AUTH_MODE=off` keeps the tool fully usable on a developer's Mac with
  `./run.sh`, and the existing NutriVisionAI `http://localhost:8766`
  integration continues to work with no token.

---

## Security Checklist

- TLS everywhere (Caddy auto-provisions certs).
- HttpOnly + Secure + SameSite=Lax session cookies.
- CSRF on all cookie-authed state-changing routes.
- API tokens hashed at rest (sha256), plaintext shown once.
- Provider storage state encrypted at rest.
- `APP_SECRET_KEY` must be ≥ 32 random bytes; refuse to boot otherwise.
- Per-user row-level scoping enforced in service layer, with tests that
  try to access another user's list and assert `403`.
- SQL: SQLModel parameterised queries only; no string concat.
- No raw HTML from providers rendered in the UI (every field passes
  through a whitelisted normaliser).
- CSP header denies inline scripts and restricts `connect-src` / `img-src`.
- Caddy rate-limit on `/api/v1/auth/login`.

---

## Open Questions

- **Do we want sharing / household lists?** Tempting (share cart with a
  spouse) but adds permissions UI. Suggest: punt until post-beta. If added,
  the model is `list.owner_user_id` + `list_members(list_id, user_id, role)`.
- **Multi-region scraping.** A user in India asking for Target prices is
  going to see US-only results. We already model ZIP and store-picker, but
  should add explicit "locale" / country at the user level.
- **Paid tier / quotas.** Whether hosted-for-free at all. Decide before
  public beta; until then, invite-only gates abuse.
- **Push notifications.** For "your basket total dropped", iOS can
  subscribe via APNs. Out of scope for this spec but noting the hook:
  `api_tokens` row can carry an optional `apns_device_token`.

---

## Non-Goals

- Mobile push notifications (see open questions).
- Price-drop alerts / background scraping for items the user isn't
  actively viewing.
- Payment / checkout integration with retailers.
- Full desktop app or browser extension.

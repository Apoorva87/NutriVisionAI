# NutriSight TODO

## Current Priorities

- Extract and import a broader Indian-food pack from the official IFCT PDF into the local catalog.
- Improve portion estimation for complex Indian meals and thalis.
- Reduce duplicate or semantically overlapping detections from the vision model.
- Validate the mobile flow on a real phone with several real meal photos.

## Product Work

- Add confidence thresholds and clearer unknown-food review states.
- Add goal presets and onboarding defaults.
- Add better history visualizations for calorie and macro trends.
- Add a lightweight "repeat last meal" or "clone meal" action for common breakfasts and snacks.
- Add personalized food-search ranking with favorites and frequent user choices.

## Nutrition Data

- Add repeatable import scripts for USDA and Indian sources.
- Add more Indian staples: chapati, dosa, idli, paneer, rajma, sambar, poha, upma.
- Add recipe/composite-food handling instead of only canonical single foods.
- Track source freshness and import provenance more explicitly.

## Model / Pipeline

- Tune Qwen3-VL prompts on a small benchmark of real meal images.
- Add confidence-aware filtering for garnish and low-value side detections.
- Add optional fallback providers for Ollama and external APIs.

## Admin / Ops

- Extend the DB portal to manage aliases and source rows, not just nutrition items.
- Add CSV/JSON import-export from the DB portal.
- Add basic auth on admin routes.
- Add Google sign-in once the app has a stable HTTPS hostname.
- Add backup/restore flow for the SQLite DB and uploaded images.

## Testing

- Add endpoint tests for admin CRUD routes.
- Add regression tests for duplicate-canonical detections and portion heuristics.
- Add end-to-end tests for save and dashboard refresh behavior.
- Add tests for meal edit (PUT) and delete endpoints.

## Documentation

- Keep `docs/EXECUTION_LOG.md` updated after each substantial pass.
- Keep `ARCHITECTURE.md` aligned with any new routes or provider integrations.
- Keep the GitHub Pages static preview aligned with template/layout changes.

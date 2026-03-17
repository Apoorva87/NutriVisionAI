# NutriSight TODO

## Current Priorities

- Extract and import a broader Indian-food pack from the official IFCT PDF into the local catalog.
- Improve portion estimation for complex Indian meals and thalis.
- Reduce duplicate or semantically overlapping detections from the vision model.
- Validate the mobile flow on a real phone with several real meal photos.
- Add richer food search ranking with favorites / recent foods / frequent user choices.

## Product Work

- Add confidence thresholds and clearer unknown-food review states.
- Add meal editing after save.
- Add optional user profile fields beyond `current_user_name`.
- Add goal presets and onboarding defaults.
- Add better history visualizations for calorie and macro trends.
- Add a lightweight "repeat last meal" or "clone meal" action for common breakfasts and snacks.
- Add recent custom-food shortcuts directly near the meal composer.

## Nutrition Data

- Add repeatable import scripts for USDA and Indian sources.
- Add more Indian staples: chapati, dosa, idli, paneer, rajma, sambar, poha, upma.
- Add recipe/composite-food handling instead of only canonical single foods.
- Track source freshness and import provenance more explicitly.
- Consider publishing a preprocessed nutrition catalog snapshot outside the app repo for faster onboarding.

## Model / Pipeline

- Tune Qwen3-VL prompts on a small benchmark of real meal images.
- Consider a second text-only reasoning pass after vision extraction if needed.
- Add confidence-aware filtering for garnish and low-value side detections.
- Add optional fallback providers for Ollama and external APIs.

## Admin / Ops

- Extend the DB portal to manage aliases and source rows, not just nutrition items.
- Add CSV/JSON import-export from the DB portal.
- Add basic auth if the app is exposed beyond a trusted LAN.
- Add backup/restore flow for the SQLite DB and uploaded images.

## Testing

- Add endpoint tests for admin CRUD routes.
- Add regression tests for duplicate-canonical detections and portion heuristics.
- Add end-to-end tests for save and dashboard refresh behavior.
- Add import tests using larger sample source payloads.

## Documentation

- Keep `docs/EXECUTION_LOG.md` updated after each substantial pass.
- Keep `ARCHITECTURE.md` aligned with any new routes or provider integrations.
- Document the expected import payload shape for nutrition catalogs more formally.

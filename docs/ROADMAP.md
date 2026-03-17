# Roadmap

## Phase 1: Foundation Hardening

- define domain schemas for detections, portion estimates, analysis results, meals, and dashboard summaries
- replace direct stub wiring with provider registries selected from config
- add settings update flow for calorie goals, macro goals, provider selection, and estimation style
- persist enough metadata to support future model explainability
- phase status: largely implemented

## Phase 2: Product Features

- meal history page with per-meal item details
- richer correction UI with canonical food search and error handling
- dashboard improvements for daily progress and recent logs
- server-side validation and tests for nutrition math and save flows
- phase status: partially implemented

## Phase 3: Local Model Integration

- Ollama vision / LLM adapter
- LM Studio adapter
- configurable API fallback adapter
- structured JSON contracts for provider outputs
- phase status: in progress

## Phase 4: Data and UX Quality

- source-backed nutrition catalog and import pipeline from USDA and Indian sources
- image compression before upload
- confidence thresholds and low-confidence review states
- better mobile-first capture experience over LAN
- phase status: partially implemented

## Handoff Rules

- Update `docs/EXECUTION_LOG.md` at the end of every Codex pass.
- Keep the log concrete: list files changed, verification performed, and the next recommended phase.
- Read the latest log entry before starting work in a new session.
- Prefer continuing the highest incomplete phase before starting a lower-priority enhancement.

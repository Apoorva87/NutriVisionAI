# Unified Log and Grocery Completion Design

## Goal

Finish and validate the uncommitted NutriVisionAI iOS work in two ordered
phases: the unified meal logging experience first, followed by the
iBuyGrocery store-price experience.

## Scope and constraints

- The app targets iOS 17+ and is generated from `ios/NutriVisionAI/project.yml`.
- Preserve existing cloud/local mode behavior, nutrition search, AI food lookup,
  local meal persistence, and the visual system.
- Do not modify or deploy the separate iBuyGrocery backend. Its current iOS
  contract is `/api/v1`, `X-API-Key`, unauthenticated `GET /healthz`, and
  authenticated `GET /auth/me`.
- Avoid destructive cleanup of unrelated uncommitted files and ignored local
  artifacts.

## Phase 1: Unified Log

`ContentView` presents `UnifiedLogView` as the Log tab. It exposes Scan,
Search, and Ask AI as input routes, all of which add `MealDraftItem` values to
the single `MealDraftStore`. `MealDraftBar` presents the compact summary, and
`MealDraftReviewSheet` provides editing and saving through the existing
cloud/local meal persistence paths.

The old `AnalyzeView` and `LogView` remain removed only after all references
and project-generation inputs confirm the replacement flow compiles. Tests
will focus on the draft's item/totals/save boundary and URL/request
construction that can run outside UI automation; an iOS simulator build will
verify SwiftUI integration.

## Phase 2: Grocery / iBuyGrocery

The grocery screen remains the destination for AI suggestions and local cart
behavior. When configured, it adds price discovery through
`IBuyGroceryClient`, showing candidates, per-store selections, live SSE
updates, and basket plans. Settings owns configuration and identity feedback;
the client owns URL normalization, `/api/v1` prefixing, and request headers.

The client must distinguish a reachable service from an authenticated
identity: `/healthz` confirms reachability without a key, while `/auth/me`
reports credential state. Failure states should be actionable and never make
the base grocery list unusable.

## Verification

1. Regenerate the Xcode project from `project.yml` and confirm all new Swift
   sources are included.
2. Run Swift package tests for pure model/service behavior when supported.
3. Build the iOS app for an available iOS simulator destination.
4. Run the repository's existing Python regression suite to confirm iOS-facing
   backend behavior was not disturbed.
5. Recheck Git status so every required source, XcodeGen input, test, and
   documentation file is included in the handoff.

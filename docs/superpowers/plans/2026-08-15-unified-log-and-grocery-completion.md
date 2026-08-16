# Unified Log and Grocery Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a buildable iOS app in which the unified Log workflow shares one meal draft and Grocery uses the iBuyGrocery `/api/v1` API contract.

**Architecture:** `MealDraftItem` and `MealDraftStore` are shared state for Scan, Search, and Ask AI. `IBuyGroceryClient` owns URL construction and API-key headers; its SwiftUI consumers remain at view boundaries. XcodeGen owns reproducible source and test inclusion.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, Foundation URLSession, XcodeGen, iOS 17+.

**Spec:** `docs/superpowers/specs/2026-08-15-unified-log-and-grocery-completion-design.md`

## Global Constraints

- Preserve cloud/local persistence, nutrition search, AI lookup, and the existing visual system.
- Keep iOS 17.0, Swift 5.9, `/api/v1` prefixing, and `X-API-Key` authentication.
- Keep `GET /healthz` unkeyed; do not modify the separate iBuyGrocery backend.
- Do not remove unrelated uncommitted or ignored local artifacts.

---

### Task 1: Add reproducible shared-draft XCTest coverage

**Files:**
- Create: `ios/NutriVisionAI/Tests/NutriVisionAITests/MealDraftItemTests.swift`
- Modify: `ios/NutriVisionAI/project.yml`
- Modify if test exposes a defect: `ios/NutriVisionAI/Models/MealDraftItem.swift`

**Interfaces:**
- Consumes: `MealDraftItem` macro properties.
- Produces: the `NutriVisionAITests` test target importing `@testable import NutriVisionAI`.

- [ ] **Step 1: Write the failing test**

```swift
func testDraftItemScalesMacrosWithGramMultiplier() {
    var item = MealDraftItem(name: "Oats", baseGrams: 50, caloriesPer100g: 400,
                             proteinPer100g: 10, carbsPer100g: 60, fatPer100g: 8,
                             provenance: .search)
    item.gramsMultiplier = 1.5
    XCTAssertEqual(item.grams, 75)
    XCTAssertEqual(item.totalCalories, 300)
    XCTAssertEqual(item.totalProtein, 7.5)
    XCTAssertEqual(item.totalCarbs, 45)
    XCTAssertEqual(item.totalFat, 6)
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `cd ios/NutriVisionAI && xcodegen generate && xcodebuild test -project NutriVisionAI.xcodeproj -scheme NutriVisionAI -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NutriVisionAITests/MealDraftItemTests/testDraftItemScalesMacrosWithGramMultiplier`

Expected: FAIL because no XCTest target exists.

- [ ] **Step 3: Add the target and minimal correction**

Add a unit-test target depending on `NutriVisionAI` in `project.yml`. Correct only the asserted macro calculation if the test reveals a mismatch.

- [ ] **Step 4: Re-run the focused test**

Run: the command in Step 2.

Expected: PASS with one XCTest executed.

- [ ] **Step 5: Commit**

```bash
git add ios/NutriVisionAI/project.yml ios/NutriVisionAI/Tests/NutriVisionAITests/MealDraftItemTests.swift ios/NutriVisionAI/Models/MealDraftItem.swift
git commit -m "test: cover meal draft macro totals"
```

### Task 2: Verify unified Log ownership and simulator integration

**Files:**
- Create: `ios/NutriVisionAI/Tests/NutriVisionAITests/MealDraftStoreTests.swift`
- Modify if test/build exposes a defect: `ios/NutriVisionAI/Views/ContentView.swift`
- Modify if test/build exposes a defect: `ios/NutriVisionAI/Views/UnifiedLogView.swift`, `ScanFlowView.swift`, `SearchFlowView.swift`, `AILookupFlowView.swift`, `MealDraftBar.swift`, `MealDraftReviewSheet.swift`

**Interfaces:**
- Consumes: `MealDraftStore.addItem(_:)`, `addItems(_:)`, and `saveMeal()`.
- Produces: a Log tab with Scan, Search, and Ask AI that all contribute to one meal draft.

- [ ] **Step 1: Write a failing shared-draft behavior test**

```swift
@MainActor
func testDraftCombinesItemsFromAllLogProvenances() {
    let store = MealDraftStore.shared
    store.clear()
    defer { store.clear() }
    store.addItems([scanItem, searchItem, aiItem])
    XCTAssertEqual(store.itemCount, 3)
    XCTAssertEqual(store.includedItems.map(\.provenance), [.scan, .search, .ai])
    XCTAssertEqual(store.totalCalories, 600)
}
```

- [ ] **Step 2: Run the behavior test and verify it fails**

Run: `cd ios/NutriVisionAI && xcodegen generate && xcodebuild test -project NutriVisionAI.xcodeproj -scheme NutriVisionAI -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NutriVisionAITests/MealDraftStoreTests/testDraftCombinesItemsFromAllLogProvenances`

Expected: FAIL because `MealDraftStoreTests` does not yet exist.

- [ ] **Step 3: Add the behavior test and correct broken ownership only**

Add the test with three independently constructed `MealDraftItem` fixtures. If the app build exposes a broken flow, route its existing result through `MealDraftStore.shared` without replacing the current scan/search/AI service call.

- [ ] **Step 4: Run behavior test and Debug simulator build**

Run: `cd ios/NutriVisionAI && xcodegen generate && xcodebuild test -project NutriVisionAI.xcodeproj -scheme NutriVisionAI -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NutriVisionAITests/MealDraftStoreTests && xcodebuild build -project NutriVisionAI.xcodeproj -scheme NutriVisionAI -destination 'platform=iOS Simulator,name=iPhone 16'`

Expected: draft behavior test and Debug simulator build pass.

- [ ] **Step 5: Commit**

```bash
git add ios/NutriVisionAI/Tests/NutriVisionAITests/MealDraftStoreTests.swift ios/NutriVisionAI/Views
git commit -m "feat: complete unified meal logging flow"
```

### Task 3: Cover the iBuyGrocery request contract

**Files:**
- Create: `ios/NutriVisionAI/Tests/NutriVisionAITests/IBuyGroceryClientTests.swift`
- Modify: `ios/NutriVisionAI/Services/IBuyGroceryClient.swift`

**Interfaces:**
- Consumes: `IBuyGroceryClient.baseURL`, `apiToken`, `eventsURL(listId:)`, and `authHeaders()`.
- Produces: `internal func requestURL(for path: String) throws -> URL`, used by every request helper and visible to `@testable` XCTest.

- [ ] **Step 1: Write the failing test**

```swift
func testRemoteRequestUsesAPIV1AndAPIKeyHeader() throws {
    let client = IBuyGroceryClient.shared
    client.baseURL = "https://grocery.example.com/"
    client.setAPIToken("sk_search_test")
    XCTAssertEqual(try client.requestURL(for: "/healthz").absoluteString,
                   "https://grocery.example.com/api/v1/healthz")
    XCTAssertEqual(client.authHeaders()["X-API-Key"], "sk_search_test")
    XCTAssertNil(client.authHeaders()["Authorization"])
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd ios/NutriVisionAI && xcodegen generate && xcodebuild test -project NutriVisionAI.xcodeproj -scheme NutriVisionAI -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NutriVisionAITests/IBuyGroceryClientTests/testRemoteRequestUsesAPIV1AndAPIKeyHeader`

Expected: FAIL because `requestURL(for:)` does not exist.

- [ ] **Step 3: Expose the minimal URL seam**

Rename private `makeURL(_:)` to internal `requestURL(for:)`; update GET, DELETE, POST, PUT, and PATCH helpers to call it. Preserve the single `/api/v1` prefix and never add a bearer header.

- [ ] **Step 4: Add and run the prefix regression test**

```swift
func testHealthAndEventURLsHaveOneAPIV1Prefix() throws {
    let client = IBuyGroceryClient.shared
    client.baseURL = "http://localhost:8766"
    XCTAssertEqual(try client.requestURL(for: "/api/v1/healthz").path, "/api/v1/healthz")
    XCTAssertEqual(client.eventsURL(listId: 42)?.path, "/api/v1/events/list/42")
}
```

Run: `cd ios/NutriVisionAI && xcodegen generate && xcodebuild test -project NutriVisionAI.xcodeproj -scheme NutriVisionAI -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NutriVisionAITests/IBuyGroceryClientTests`

Expected: PASS with both tests.

- [ ] **Step 5: Commit**

```bash
git add ios/NutriVisionAI/Services/IBuyGroceryClient.swift ios/NutriVisionAI/Tests/NutriVisionAITests/IBuyGroceryClientTests.swift
git commit -m "test: cover grocery API request contract"
```

### Task 4: Verify grocery views and final delivery

**Files:**
- Create: `ios/NutriVisionAI/Tests/NutriVisionAITests/IBuyGroceryErrorTests.swift`
- Modify: `ios/CLAUDE.md`
- Modify if test/build exposes a defect: `GroceryListView.swift`, `GroceryStorePricesView.swift`, `GroceryCandidatesSheet.swift`, `GroceryBasketPlanView.swift`, `IBuyGrocerySettingsView.swift`, `IBuyGrocerySSEClient.swift`

**Interfaces:**
- Consumes: `healthz()`, `authMe()`, `eventsURL(listId:)`, candidate selection, and basket operations.
- Produces: reachable-service and authenticated-identity feedback plus a grocery list that remains usable after provider failures.

- [ ] **Step 1: Write a failing grocery error behavior test**

```swift
func testUnauthorizedErrorGivesSettingsRecoveryGuidance() {
    XCTAssertEqual(IBuyGroceryError.unauthorized.errorDescription,
                   "Store Prices backend rejected the API token. Check Settings → Store Prices.")
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd ios/NutriVisionAI && xcodegen generate && xcodebuild test -project NutriVisionAI.xcodeproj -scheme NutriVisionAI -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NutriVisionAITests/IBuyGroceryErrorTests/testUnauthorizedErrorGivesSettingsRecoveryGuidance`

Expected: FAIL because `IBuyGroceryErrorTests` does not yet exist.

- [ ] **Step 3: Add the behavior test and repair failing view boundaries only**

Add the test. If the build exposes a failing grocery view boundary, use its existing client/SSE call, display caught errors in the owning view, and retain access to local grocery suggestions.

- [ ] **Step 4: Run all verification**

Run: `cd ios/NutriVisionAI && xcodegen generate && xcodebuild test -project NutriVisionAI.xcodeproj -scheme NutriVisionAI -destination 'platform=iOS Simulator,name=iPhone 16' && xcodebuild build -project NutriVisionAI.xcodeproj -scheme NutriVisionAI -destination 'platform=iOS Simulator,name=iPhone 16'`

Run: `pytest -q`

Expected: all XCTest cases, the Debug simulator build, and Python regression tests pass.

- [ ] **Step 5: Document and commit**

Update `ios/CLAUDE.md` with `xcodegen generate` plus the grocery `/api/v1` and `X-API-Key` contract. Stage only implementation, tests, XcodeGen input, relevant docs, and deletion records, then commit with `feat: complete unified log and grocery flows`.

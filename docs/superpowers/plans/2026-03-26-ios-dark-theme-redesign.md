# iOS Dark Theme Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the NutriVisionAI iOS app with a "Neon Vitality" dark theme (true black + purple/violet gradients), add AI meal suggestions to the dashboard, portion size controls to scan/log, and multi-provider AI settings.

**Architecture:** All changes are iOS-side only — the backend is untouched. A centralized `Theme.swift` provides all colors/gradients. New features (meal suggestions, portion selector, quick food search) use existing backend endpoints. The app remains a thin UI client.

**Tech Stack:** SwiftUI (iOS 17+), Swift Charts, Foundation networking, Security framework (Keychain)

**Spec:** `docs/superpowers/specs/2026-03-26-ios-dark-theme-redesign-design.md`

---

## File Map

### New Files (in `ios/NutriVisionAI/`)

| File | Responsibility |
|------|---------------|
| `Views/Theme.swift` | All color tokens, gradients, card styles as static properties |
| `Views/Components/GradientButton.swift` | Reusable gradient button with glow shadow |
| `Views/Components/PortionSelector.swift` | S/M/L/XL portion picker, used in Scan + Log |
| `Views/MealSuggestionsView.swift` | AI meal plan section embedded in Dashboard |
| `Views/QuickFoodSearchSheet.swift` | Compact food search half-sheet for Scan results |
| `Services/KeychainHelper.swift` | Simple Keychain CRUD for API keys |

### Modified Files

| File | What Changes |
|------|-------------|
| `NutriVisionAIApp.swift` | `.preferredColorScheme(.dark)`, `.tint(Theme.accent)` |
| `Views/ContentView.swift` | Tab bar appearance config (dark background, violet selection) |
| `Models/NutritionModels.swift` | Add LLM chat models, MealSuggestion |
| `Services/APIClient.swift` | Add `llmChat()` method |
| `Views/DashboardView.swift` | Theme all sub-views, embed MealSuggestionsView |
| `Views/AnalyzeView.swift` | Theme, fix scaling bug, add PortionSelector + QuickFoodSearchSheet |
| `Views/LogView.swift` | Theme, add PortionSelector to meal builder items |
| `Views/HistoryView.swift` | Theme colors, gradient chart bars, styled pills |
| `Views/SettingsView.swift` | Theme, multi-provider cards, cloud provider detail sheets |

---

## Task 1: Theme Foundation + App Shell

**Files:**
- Create: `ios/NutriVisionAI/Views/Theme.swift`
- Create: `ios/NutriVisionAI/Views/Components/GradientButton.swift`
- Modify: `ios/NutriVisionAI/NutriVisionAIApp.swift`
- Modify: `ios/NutriVisionAI/Views/ContentView.swift`

- [ ] **Step 1: Create `Theme.swift`**

Create `ios/NutriVisionAI/Views/Theme.swift` with all color tokens from the spec:

```swift
import SwiftUI

enum Theme {
    // MARK: - Backgrounds
    static let background = Color(red: 15/255, green: 15/255, blue: 15/255)  // #0f0f0f
    static let cardSurface = Color.white.opacity(0.03)
    static let cardBorder = Color.white.opacity(0.06)
    static let cardGlow = Color(red: 167/255, green: 139/255, blue: 250/255).opacity(0.12)

    // MARK: - Accent
    static let accent = Color(red: 167/255, green: 139/255, blue: 250/255)  // #a78bfa
    static let accentGradientStart = Color(red: 124/255, green: 58/255, blue: 237/255)  // #7c3aed
    static let accentGradientEnd = Color(red: 168/255, green: 85/255, blue: 247/255)  // #a855f7
    static let accentGradient = LinearGradient(
        colors: [accentGradientStart, accentGradientEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Text
    static let textPrimary = Color(red: 226/255, green: 232/255, blue: 240/255)  // #e2e8f0
    static let textSecondary = Color(red: 148/255, green: 163/255, blue: 184/255)  // #94a3b8
    static let textMuted = Color(red: 71/255, green: 85/255, blue: 105/255)  // #475569

    // MARK: - Macro Gradients
    static let proteinGradient = LinearGradient(
        colors: [Color(red: 56/255, green: 189/255, blue: 248/255), Color(red: 129/255, green: 140/255, blue: 248/255)],
        startPoint: .leading, endPoint: .trailing
    )
    static let carbsGradient = LinearGradient(
        colors: [Color(red: 250/255, green: 204/255, blue: 21/255), Color(red: 251/255, green: 146/255, blue: 60/255)],
        startPoint: .leading, endPoint: .trailing
    )
    static let fatGradient = LinearGradient(
        colors: [Color(red: 251/255, green: 113/255, blue: 133/255), Color(red: 232/255, green: 121/255, blue: 249/255)],
        startPoint: .leading, endPoint: .trailing
    )

    // Solid macro colors (for text labels)
    static let proteinColor = Color(red: 129/255, green: 140/255, blue: 248/255)  // #818cf8
    static let carbsColor = Color(red: 251/255, green: 191/255, blue: 36/255)  // #fbbf24
    static let fatColor = Color(red: 251/255, green: 113/255, blue: 133/255)  // #fb7185

    // MARK: - Semantic
    static let positive = Color(red: 34/255, green: 211/255, blue: 238/255)  // #22d3ee
    static let destructive = Color(red: 239/255, green: 68/255, blue: 68/255)  // #ef4444
    static let successStart = Color(red: 34/255, green: 197/255, blue: 94/255)  // #22c55e
    static let successEnd = Color(red: 22/255, green: 163/255, blue: 74/255)  // #16a34a
    static let successGradient = LinearGradient(
        colors: [successStart, successEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let calorieValue = Color(red: 192/255, green: 132/255, blue: 252/255)  // #c084fc

    // MARK: - Card Style Modifier
    static func cardStyle(glow: Bool = false) -> some ViewModifier {
        CardStyleModifier(glow: glow)
    }

    // MARK: - Thumbnail gradient backgrounds
    static let thumbnailGradients: [LinearGradient] = [
        LinearGradient(colors: [Color(red: 76/255, green: 29/255, blue: 149/255), Color(red: 109/255, green: 40/255, blue: 217/255)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 30/255, green: 58/255, blue: 95/255), Color(red: 37/255, green: 99/255, blue: 235/255)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 127/255, green: 29/255, blue: 29/255), Color(red: 220/255, green: 38/255, blue: 38/255)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 6/255, green: 95/255, blue: 70/255), Color(red: 4/255, green: 120/255, blue: 87/255)], startPoint: .topLeading, endPoint: .bottomTrailing),
    ]
}

struct CardStyleModifier: ViewModifier {
    let glow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .background(Theme.cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(glow ? Theme.cardGlow : Theme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: (glow && !reduceMotion) ? Theme.accent.opacity(0.06) : .clear, radius: 12)
    }
}

extension View {
    func themedCard(glow: Bool = false) -> some View {
        modifier(CardStyleModifier(glow: glow))
    }
}

// MARK: - Accessibility: Reduce Motion helper

/// Generic modifier that swaps spring animations for `.default` when reduceMotion is on.
struct ReduceMotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .default : animation, value: value)
    }
}

extension View {
    /// Use instead of `.animation(...)` on spring/glow animations to respect reduceMotion.
    func motionSafeAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReduceMotionModifier(animation: animation, value: value))
    }
}
```

- [ ] **Step 2: Create `GradientButton.swift`**

Create `ios/NutriVisionAI/Views/Components/GradientButton.swift`:

```swift
import SwiftUI

struct GradientButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    if let icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isDisabled ? Color.gray : Theme.accentGradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: isDisabled ? .clear : Theme.accentGradientStart.opacity(0.3), radius: 10, y: 4)
        }
        .disabled(isLoading || isDisabled)
    }
}
```

- [ ] **Step 3: Apply dark mode to app shell**

Modify `ios/NutriVisionAI/NutriVisionAIApp.swift` — add `.preferredColorScheme(.dark)` and `.tint(Theme.accent)`:

```swift
import SwiftUI

@main
struct NutriVisionAIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
```

- [ ] **Step 4: Style the tab bar**

Modify `ios/NutriVisionAI/Views/ContentView.swift` — add an `init()` to configure `UITabBarAppearance` with dark styling, and add `.onAppear` for the tab bar config:

After the existing `TabView(selection: $selectedTab) { ... }` closing brace, before the closing of `body`, add:

```swift
.onAppear {
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor(Theme.background)
    appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Theme.accent)
    appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.accent)]
    appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Theme.textMuted)
    appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.textMuted)]
    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
}
```

- [ ] **Step 5: Verify in simulator**

Run: Build and run in Xcode on iPhone 15 Pro simulator.
Expected: App launches with dark background, violet-tinted tab bar, all 5 tabs still functional.

- [ ] **Step 6: Commit**

```bash
git add ios/NutriVisionAI/Views/Theme.swift ios/NutriVisionAI/Views/Components/GradientButton.swift ios/NutriVisionAI/NutriVisionAIApp.swift ios/NutriVisionAI/Views/ContentView.swift
git commit -m "feat: add Theme foundation, GradientButton, dark mode shell"
```

---

## Task 2: New Models + API Client + KeychainHelper

**Files:**
- Modify: `ios/NutriVisionAI/Models/NutritionModels.swift` (append after line 388)
- Modify: `ios/NutriVisionAI/Services/APIClient.swift` (add method after line 140)
- Create: `ios/NutriVisionAI/Services/KeychainHelper.swift`

- [ ] **Step 1: Add LLM and MealSuggestion models**

Append to `ios/NutriVisionAI/Models/NutritionModels.swift` after the `AnyCodableValue` enum:

```swift
// MARK: - LLM Chat (for meal suggestions)

struct LLMChatRequest: Codable {
    let model: String
    let messages: [LLMMessage]
    let temperature: Double?
}

struct LLMMessage: Codable {
    let role: String
    let content: String
}

struct LLMChatResponse: Codable {
    let choices: [LLMChoice]
}

struct LLMChoice: Codable {
    let message: LLMMessage
}

// MARK: - Meal Suggestion

struct MealSuggestion: Codable, Identifiable {
    var id: String { "\(meal)-\(option)" }
    let meal: String
    let option: Int
    let food: String
    let ingredients: String
    let reason: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case meal, option, food, ingredients, reason, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}
```

- [ ] **Step 2: Add `llmChat` method to APIClient**

Add after the `aiLookup` method in `ios/NutriVisionAI/Services/APIClient.swift` (after line 140, before `// MARK: - HTTP Helpers`):

```swift
// MARK: - LLM Chat

func llmChat(model: String, messages: [LLMMessage], temperature: Double? = 0.7) async throws -> String {
    let request = LLMChatRequest(model: model, messages: messages, temperature: temperature)
    let response: LLMChatResponse = try await post("/llm/chat", body: request)
    guard let content = response.choices.first?.message.content else {
        throw NutriError.api(statusCode: 500, message: "Empty LLM response")
    }
    return content
}
```

- [ ] **Step 3: Create `KeychainHelper.swift`**

Create `ios/NutriVisionAI/Services/KeychainHelper.swift`:

```swift
import Foundation
import Security

enum KeychainHelper {
    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status): return "Keychain save failed: \(status)"
            case .deleteFailed(let status): return "Keychain delete failed: \(status)"
            }
        }
    }

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
```

- [ ] **Step 4: Verify build**

Build the project in Xcode. All new models and services should compile without errors.

- [ ] **Step 5: Commit**

```bash
git add ios/NutriVisionAI/Models/NutritionModels.swift ios/NutriVisionAI/Services/APIClient.swift ios/NutriVisionAI/Services/KeychainHelper.swift
git commit -m "feat: add LLM chat models, APIClient.llmChat, KeychainHelper"
```

---

## Task 3: PortionSelector Component

**Files:**
- Create: `ios/NutriVisionAI/Views/Components/PortionSelector.swift`

- [ ] **Step 1: Create `PortionSelector.swift`**

Create `ios/NutriVisionAI/Views/Components/PortionSelector.swift`:

```swift
import SwiftUI

struct PortionSelector: View {
    let baseGrams: Double
    @Binding var selectedMultiplier: Double

    private let options: [(label: String, fullName: String, multiplier: Double)] = [
        ("S", "Small", 0.5),
        ("M", "Medium", 1.0),
        ("L", "Large", 1.5),
        ("XL", "Extra Large", 2.0),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.label) { option in
                let isSelected = selectedMultiplier == option.multiplier
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMultiplier = option.multiplier
                    }
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                } label: {
                    VStack(spacing: 2) {
                        Text(option.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("~\(Int(baseGrams * option.multiplier))g")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isSelected ? Theme.accent.opacity(0.12) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Theme.accent.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                }
                .accessibilityLabel("\(option.fullName), approximately \(Int(baseGrams * option.multiplier)) grams")
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Build the project. The component should compile standalone.

- [ ] **Step 3: Commit**

```bash
git add ios/NutriVisionAI/Views/Components/PortionSelector.swift
git commit -m "feat: add PortionSelector component (S/M/L/XL)"
```

---

## Task 4: Theme Dashboard

**Files:**
- Modify: `ios/NutriVisionAI/Views/DashboardView.swift`

This task themes all existing Dashboard sub-views. The AI suggestions section is added in Task 5.

- [ ] **Step 1: Theme `CalorieSummaryCard`**

In `ios/NutriVisionAI/Views/DashboardView.swift`, replace the `CalorieSummaryCard` body (lines 97-142) with themed version:

Key changes:
- Replace `Color(.secondarySystemGroupedBackground)` → `.themedCard(glow: true)`
- Replace `Color(.systemGray5)` ring stroke → `Theme.accent.opacity(0.1)`
- Replace `progressColor.gradient` → `Theme.accentGradient` on the ring stroke
- Replace `.foregroundStyle(.green)` on remaining → `Theme.positive`
- Replace `.foregroundStyle(.red)` on over → `Theme.destructive`
- Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to `CalorieSummaryCard`
- Add `.shadow(color: reduceMotion ? .clear : Theme.accent.opacity(0.4), radius: 8)` to progress ring
- Add `.motionSafeAnimation(.spring(duration: 0.6), value: progress)` to the ring's trim modifier
- Replace `"Today's Calories"` foreground → `Theme.textSecondary`
- Replace calorie number color → `Theme.textPrimary`
- Replace "of X kcal" → `Theme.textSecondary`

- [ ] **Step 2: Theme `MacroProgressSection` and `MacroProgressBar`**

Key changes to `MacroProgressSection`:
- Replace `Color(.secondarySystemGroupedBackground)` → `.themedCard()`
- Replace `.font(.headline)` "Macros" → add `.foregroundStyle(Theme.textPrimary)`

Key changes to `MacroProgressBar`:
- Replace `color: .blue` → use `Theme.proteinGradient` as bar fill
- Replace `color: .orange` → use `Theme.carbsGradient`
- Replace `color: .purple` → use `Theme.fatGradient`
- Replace `Color(.systemGray5)` track → `Color.white.opacity(0.06)`
- Replace `color.gradient` fill → the corresponding gradient
- Add `.motionSafeAnimation(.spring(duration: 0.4), value: currentValue)` to the bar fill geometry
- Text colors: label `Theme.textSecondary`, value `Theme.textPrimary`

- [ ] **Step 3: Theme `RecentMealsSection` and `MealRowCard`**

Key changes to `RecentMealsSection`:
- Replace `Color(.secondarySystemGroupedBackground)` → `.themedCard()`
- Title color → `Theme.textPrimary`, badge → `Theme.textMuted`

Key changes to `MealRowCard`:
- Replace placeholder `Color(.systemGray5)` → use `Theme.thumbnailGradients[meal.id % Theme.thumbnailGradients.count]`
- Meal name → `Theme.textPrimary`
- Time → `Theme.textMuted`
- Calorie number → `Theme.calorieValue`
- "kcal" → `Theme.textMuted`
- Chevron → `Theme.textMuted`

- [ ] **Step 4: Theme `MealDetailSheet` and `NutritionStatView`**

Key changes:
- Replace all `Color(.secondarySystemGroupedBackground)` → `.themedCard()`
- Stat values → `Theme.textPrimary`
- Labels → `Theme.textSecondary`
- Delete button → `Theme.destructive`
- Background of ScrollView → `Theme.background`

- [ ] **Step 5: Set Dashboard ScrollView background**

Add `.background(Theme.background)` to the ScrollView in `DashboardView.body` and `.scrollContentBackground(.hidden)` if inside a NavigationStack.

Also add `.toolbarBackground(Theme.background, for: .navigationBar)` to the NavigationStack.

- [ ] **Step 6: Verify in simulator**

Build and run. Dashboard tab should show dark themed calorie ring with violet glow, gradient macro bars, themed meal cards.

- [ ] **Step 7: Commit**

```bash
git add ios/NutriVisionAI/Views/DashboardView.swift
git commit -m "feat: theme Dashboard with Neon Vitality dark design"
```

---

## Task 5: AI Meal Suggestions on Dashboard

**Files:**
- Create: `ios/NutriVisionAI/Views/MealSuggestionsView.swift`
- Modify: `ios/NutriVisionAI/Views/DashboardView.swift` (embed the new view)

- [ ] **Step 1: Create `MealSuggestionsView.swift`**

Create `ios/NutriVisionAI/Views/MealSuggestionsView.swift`:

```swift
import SwiftUI

struct MealSuggestionsView: View {
    let summary: DashboardSummary
    let recentMeals: [MealRecord]
    let settings: SettingsResponse?

    @State private var suggestions: [MealSuggestion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cravingInput = ""
    @State private var calorieBudget: Int = 0

    private var remainingSlots: [(name: String, icon: String, calorieShare: Double)] {
        let hour = Calendar.current.component(.hour, from: Date())
        var slots: [(String, String, Double)] = []
        if hour < 10 { slots.append(("breakfast", "☀️", 0.20)) }
        if hour < 14 { slots.append(("lunch", "🍽", 0.35)) }
        if hour < 17 { slots.append(("snack", "🕓", 0.10)) }
        if hour < 21 { slots.append(("dinner", "🌙", 0.35)) }
        return slots
    }

    private var suggestionsGrouped: [(slot: String, icon: String, budget: Int, options: [MealSuggestion])] {
        remainingSlots.compactMap { slot in
            let options = suggestions.filter { $0.meal == slot.name }.sorted { $0.option < $1.option }
            let budget = Int(Double(calorieBudget) * slot.calorieShare)
            return (slot.name, slot.icon, budget, options)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Meal Plan", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    Task { await loadSuggestions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Theme.textMuted)
                }
            }

            // Controls: craving + budget
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(Theme.textMuted)
                        .font(.caption)
                    TextField("e.g. indian, pasta...", text: $cravingInput)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .onSubmit { Task { await loadSuggestions() } }
                }
                .padding(8)
                .background(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 6) {
                    Button { calorieBudget = max(0, calorieBudget - 100) } label: {
                        Text("−").foregroundStyle(Theme.textMuted)
                    }
                    Text("\(calorieBudget) cal")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                    Button { calorieBudget += 100 } label: {
                        Text("+").foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Content
            if remainingSlots.isEmpty {
                HStack {
                    Spacer()
                    Text("You're all set for today!")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if calorieBudget < 50 {
                HStack {
                    Spacer()
                    Text("You've hit your calorie goal!")
                        .font(.subheadline)
                        .foregroundStyle(Theme.positive)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if isLoading {
                ForEach(remainingSlots, id: \.name) { slot in
                    ShimmerCard()
                }
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.destructive)
                    NavigationLink("Configure AI in Settings") {
                        SettingsView()
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(suggestionsGrouped, id: \.slot) { group in
                    MealSlotCard(
                        slotName: group.slot.capitalized,
                        icon: group.icon,
                        budget: group.budget,
                        options: group.options
                    )
                    .transition(.opacity.animation(.easeIn(duration: 0.3)))
                }
            }
            .animation(.easeIn(duration: 0.3), value: suggestions.count)
        }
        .padding()
        .themedCard()
        .task {
            calorieBudget = Int(summary.remainingCalories)
            if calorieBudget >= 50 && !remainingSlots.isEmpty {
                await loadSuggestions()
            }
        }
    }

    private func loadSuggestions() async {
        isLoading = true
        errorMessage = nil

        let model = settings?.modelProvider ?? "default"
        let recentList = recentMeals.map { $0.mealName }.joined(separator: ", ")
        let slotsStr = remainingSlots.map { $0.name }.joined(separator: ", ")
        let budgetBreakdown = remainingSlots.map { "\($0.name): \(Int(Double(calorieBudget) * $0.calorieShare)) cal" }.joined(separator: ", ")
        let preference = cravingInput.isEmpty ? "healthy balanced meals" : cravingInput

        let prompt = """
        You are a nutrition assistant. The user has \(calorieBudget) calories remaining today.
        Remaining macros: protein \(Int(Double(summary.macroGoals.proteinG) - summary.proteinG))g, carbs \(Int(Double(summary.macroGoals.carbsG) - summary.carbsG))g, fat \(Int(Double(summary.macroGoals.fatG) - summary.fatG))g.
        Current time: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)). Remaining meal slots: \(slotsStr).
        Recently eaten: \(recentList.isEmpty ? "nothing yet" : recentList).
        User preference: \(preference).

        Suggest 2 options per remaining meal slot. Return ONLY a JSON array:
        [{"meal":"dinner","option":1,"food":"...","ingredients":"...","reason":"...","calories":500,"protein_g":35,"carbs_g":50,"fat_g":15}, ...]

        Calorie budget per slot: \(budgetBreakdown).
        Do not repeat foods from recently eaten list.
        """

        let messages = [
            LLMMessage(role: "system", content: prompt),
            LLMMessage(role: "user", content: "Generate meal suggestions now."),
        ]

        do {
            let content = try await APIClient.shared.llmChat(model: model, messages: messages)
            // Parse JSON array from content
            if let jsonStart = content.firstIndex(of: "["),
               let jsonEnd = content.lastIndex(of: "]") {
                let jsonString = String(content[jsonStart...jsonEnd])
                if let data = jsonString.data(using: .utf8) {
                    suggestions = try JSONDecoder().decode([MealSuggestion].self, from: data)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Sub-views

private struct MealSlotCard: View {
    let slotName: String
    let icon: String
    let budget: Int
    let options: [MealSuggestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(icon) \(slotName) · ~\(budget) cal")
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.accentGradientStart)

            HStack(spacing: 8) {
                ForEach(options) { option in
                    SuggestionOption(suggestion: option)
                }
            }
        }
        .padding(14)
        .background(Theme.accent.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct SuggestionOption: View {
    let suggestion: MealSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.food)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Text(suggestion.ingredients)
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text("P: \(Int(suggestion.proteinG))g")
                    .foregroundStyle(Theme.proteinColor)
                Text("C: \(Int(suggestion.carbsG))g")
                    .foregroundStyle(Theme.carbsColor)
                Text("F: \(Int(suggestion.fatG))g")
                    .foregroundStyle(Theme.fatColor)
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ShimmerCard: View {
    @State private var shimmer = false
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(shimmer ? 0.06 : 0.02))
            .frame(height: 100)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: shimmer)
            .onAppear { shimmer = true }
    }
}
```

- [ ] **Step 2: Embed in DashboardView**

In `ios/NutriVisionAI/Views/DashboardView.swift`, inside the `VStack(spacing: 24)` that contains `CalorieSummaryCard`, `MacroProgressSection`, and `RecentMealsSection`, add after `RecentMealsSection`:

```swift
// AI Meal Suggestions
MealSuggestionsView(
    summary: data.summary,
    recentMeals: data.recentMeals,
    settings: data.settings
)
```

- [ ] **Step 3: Verify in simulator**

Build and run. Dashboard should show the Meal Plan section below Recent Meals. If the backend LLM is not configured, it should show the error state with "Configure AI in Settings" link.

- [ ] **Step 4: Commit**

```bash
git add ios/NutriVisionAI/Views/MealSuggestionsView.swift ios/NutriVisionAI/Views/DashboardView.swift
git commit -m "feat: add AI meal suggestions section to Dashboard"
```

---

## Task 6: Theme + Portion Controls on Scan (AnalyzeView)

**Files:**
- Modify: `ios/NutriVisionAI/Views/AnalyzeView.swift`
- Create: `ios/NutriVisionAI/Views/QuickFoodSearchSheet.swift`

This is the largest single task. It themes all AnalyzeView sub-views, fixes the scaling bug, adds PortionSelector to results, and adds the QuickFoodSearchSheet.

- [ ] **Step 1: Fix the scaling bug in computed properties**

In `ios/NutriVisionAI/Views/AnalyzeView.swift`, replace the four computed properties (lines 18-32):

```swift
private var totalCalories: Double {
    editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.calories * $1.gramsMultiplier }
}

private var totalProtein: Double {
    editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.proteinG * $1.gramsMultiplier }
}

private var totalCarbs: Double {
    editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.carbsG * $1.gramsMultiplier }
}

private var totalFat: Double {
    editableItems.filter { $0.isIncluded }.reduce(0) { $0 + $1.item.fatG * $1.gramsMultiplier }
}
```

- [ ] **Step 2: Theme `ImageCaptureView`**

Key changes:
- Camera icon: add `.shadow(color: Theme.accent.opacity(0.3), radius: 20)` and `.foregroundStyle(Theme.textSecondary)`
- Title: `.foregroundStyle(Theme.textPrimary)`
- Description: `.foregroundStyle(Theme.textSecondary)`
- "Take Photo" button: replace with `GradientButton(title: "Take Photo", icon: "camera.fill") { showCamera = true }`
- "Choose from Library" PhotosPicker: style with `Theme.cardSurface` bg, `Theme.cardBorder` overlay, `Theme.textPrimary` text

- [ ] **Step 3: Theme `AnalyzingProgressView`**

- Replace `.tint(.white)` → keep
- Replace `.foregroundStyle(.white)` → keep (on dark overlay)
- Ensure `.black.opacity(0.4)` overlay stays

- [ ] **Step 4: Theme `AnalysisResultsView` and add PortionSelector**

Key changes to `AnalysisResultsView`:
- Replace `Color.accentColor` save button → `GradientButton`
- Replace `Color(.secondarySystemGroupedBackground)` → `.themedCard()`
- "Detected Items" heading → `Theme.textPrimary`

- [ ] **Step 5: Add PortionSelector to `AnalysisItemRow`**

In `AnalysisItemRow`, after the existing content but before the confidence indicator, add the portion selector. This requires changing `AnalysisItemRow` to use a `@Binding var item: EditableAnalysisItem` (it already does).

Add `PortionSelector(baseGrams: item.item.estimatedGrams, selectedMultiplier: $item.gramsMultiplier)` below the food info HStack, conditionally shown when `item.isIncluded`.

Also:
- Replace checkbox green → `Theme.successStart`
- Replace calorie text color → `Theme.calorieValue`
- Replace confidence `.foregroundStyle(.secondary)` → `Theme.textMuted`
- Replace "Not in database" warning `.foregroundStyle(.orange)` → keep orange
- Replace `Color(.secondarySystemGroupedBackground)` → `.themedCard()`

- [ ] **Step 6: Theme `NutritionSummaryBanner`**

Replace `Color(.secondarySystemGroupedBackground)` → `Theme.accent.opacity(0.06)` bg with `Theme.accent.opacity(0.12)` border.
Color the macro values: protein → `Theme.proteinColor`, carbs → `Theme.carbsColor`, fat → `Theme.fatColor`.
Add `.contentTransition(.numericText())` to all calorie/macro value `Text` views and wrap state changes in `withAnimation`.

- [ ] **Step 7: Verify in simulator**

Build and run. Scan tab should show themed capture view, themed results with portion selectors, and correct scaled totals.

- [ ] **Step 8: Commit**

```bash
git add ios/NutriVisionAI/Views/AnalyzeView.swift
git commit -m "feat: theme Scan view, fix scaling bug, add portion controls"
```

---

## Task 7: Quick Food Search on Scan Results

**Files:**
- Modify: `ios/NutriVisionAI/Views/AnalyzeView.swift`
- Create: `ios/NutriVisionAI/Views/QuickFoodSearchSheet.swift`

- [ ] **Step 1: Add `@State private var showQuickSearch = false` to `AnalyzeView`**

And after the detected items ForEach in `AnalysisResultsView`, add a dashed-border button:

```swift
Button { showQuickSearch = true } label: {
    HStack {
        Image(systemName: "magnifyingglass")
        Text("Add more items from database...")
    }
    .font(.caption)
    .foregroundStyle(Theme.accentGradientStart)
    .frame(maxWidth: .infinity)
    .padding(10)
    .background(Color.white.opacity(0.03))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
            .foregroundStyle(Theme.accent.opacity(0.2))
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
}
.padding(.horizontal)
```

Add `.sheet(isPresented: $showQuickSearch)` presenting `QuickFoodSearchSheet`.

- [ ] **Step 2: Create `QuickFoodSearchSheet.swift`**

Create `ios/NutriVisionAI/Views/QuickFoodSearchSheet.swift`:

```swift
import SwiftUI

struct QuickFoodSearchSheet: View {
    let onAddItem: (EditableAnalysisItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textMuted)
                    TextField("Search foods...", text: $query)
                        .foregroundStyle(Theme.textPrimary)
                        .submitLabel(.search)
                        .onSubmit { search() }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()

                Divider().background(Color.white.opacity(0.04))

                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty && !query.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { food in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.canonicalName.capitalized)
                                    .font(.body)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(Int(food.servingGrams))g · \(Int(food.calories)) cal")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Button {
                                addFood(food)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Theme.successStart)
                            }
                        }
                        .listRowBackground(Theme.cardSurface)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        Task {
            do {
                let response = try await APIClient.shared.searchFoods(query: query)
                await MainActor.run {
                    results = response.items
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    results = []
                    isSearching = false
                }
            }
        }
    }

    private func addFood(_ food: FoodItem) {
        let item = AnalysisItem(
            detectedName: food.canonicalName,
            canonicalName: food.canonicalName,
            portionLabel: "1 serving",
            estimatedGrams: food.servingGrams,
            uncertainty: "low",
            confidence: 1.0,
            calories: food.calories,
            proteinG: food.proteinG,
            carbsG: food.carbsG,
            fatG: food.fatG,
            visionConfidence: 0.0,
            dbMatch: true,
            nutritionAvailable: true
        )
        onAddItem(EditableAnalysisItem(item: item))
        dismiss()
    }
}
```

- [ ] **Step 3: Verify in simulator**

Build and run. Scan results should show the "Add more items" dashed button and the quick food search sheet.

- [ ] **Step 4: Commit**

```bash
git add ios/NutriVisionAI/Views/AnalyzeView.swift ios/NutriVisionAI/Views/QuickFoodSearchSheet.swift
git commit -m "feat: add quick food search sheet to Scan results"
```

---

## Task 8: Theme + Portion Controls on Log

**Files:**
- Modify: `ios/NutriVisionAI/Views/LogView.swift`

- [ ] **Step 1: Add `gramsMultiplier` to `MealBuilderItem`**

In `MealBuilderItem` struct (line ~228), add a new property:

```swift
var gramsMultiplier: Double = 1.0
```

And update the computed properties to use it:

```swift
var grams: Double { baseGrams * gramsMultiplier }
var totalCalories: Double { grams * caloriesPer100g / 100 }
var totalProtein: Double { grams * proteinPer100g / 100 }
var totalCarbs: Double { grams * carbsPer100g / 100 }
var totalFat: Double { grams * fatPer100g / 100 }
```

Note: Remove the existing `var grams: Double` stored property and make it computed. Keep `baseGrams` as the stored property (it's already there).

- [ ] **Step 2: Theme `MealBuilderSummary`**

Key changes:
- Replace `Color(.secondarySystemGroupedBackground)` → `.themedCard(glow: true)`
- "Building Meal" → `Theme.textPrimary`
- Item count/cal → `Theme.textMuted`
- Macro labels: P → `Theme.proteinColor`, C → `Theme.carbsColor`, F → `Theme.fatColor`
- Save button: gradient capsule with `Theme.accentGradient`
- Remove minus: `.foregroundStyle(Theme.destructive)`

- [ ] **Step 3: Add PortionSelector to `MealBuilderItemRow`**

Change `MealBuilderItemRow` to take a `@Binding var item: MealBuilderItem` instead of `let item`. Add `PortionSelector` below the item info:

```swift
PortionSelector(
    baseGrams: item.baseGrams,
    selectedMultiplier: $item.gramsMultiplier
)
.padding(.leading, 22)
```

Update `MealBuilderSummary` to pass bindings: change `ForEach(items)` to `ForEach($items)` — but since `items` is a `let`, you'll need to restructure so the parent view owns the `@Binding`.

The simplest approach: make `MealBuilderSummary` take `@Binding var items: [MealBuilderItem]` instead of `let items`.

- [ ] **Step 4: Theme `FoodSearchSection`**

Key changes:
- Search bar: `Color.white.opacity(0.04)` bg, `RoundedRectangle` with `Color.white.opacity(0.06)` stroke
- Search icon/text: `Theme.textMuted`
- "Search" button: `.buttonStyle(.borderedProminent)` with `.tint(Theme.accentGradientStart)`
- Plus circles: `Theme.successGradient` background

- [ ] **Step 5: Theme `FoodSearchResultRow`, `CustomFoodRow`, `AIFoodLookupSheet`, `AIFoodResultCard`**

Apply consistent theming:
- All `Color(.secondarySystemGroupedBackground)` → `.themedCard()`
- Food names → `Theme.textPrimary`
- Details/captions → `Theme.textMuted`
- Plus circles → green gradient
- Macro labels → colored (protein blue, carbs gold, fat pink)
- AI sparkle → `Theme.accent`
- "AI Estimate" badge → `Theme.accent`

- [ ] **Step 6: Theme segmented control and overall LogView**

- Add `.scrollContentBackground(.hidden)` and `.background(Theme.background)` to lists
- Segmented: use `.pickerStyle(.segmented)` with custom appearance or overlay technique

- [ ] **Step 7: Verify in simulator**

Build and run. Log tab: themed search, portion controls in meal builder, themed results and custom foods.

- [ ] **Step 8: Commit**

```bash
git add ios/NutriVisionAI/Views/LogView.swift
git commit -m "feat: theme Log view, add portion controls to meal builder"
```

---

## Task 9: Theme History

**Files:**
- Modify: `ios/NutriVisionAI/Views/HistoryView.swift`

- [ ] **Step 1: Theme `DaysSelectorView`**

Replace the button styling:
- Active pill: `Theme.accentGradient` bg, `.white` text, `.shadow(color: Theme.accentGradientStart.opacity(0.3), radius: 6)`
- Inactive pill: `Color.white.opacity(0.04)` bg, `Color.white.opacity(0.06)` stroke, `Theme.textSecondary` text
- Use `Capsule()` clip shape (already done)

- [ ] **Step 2: Theme `CalorieTrendChart`**

Key changes:
- Replace `Color(.secondarySystemGroupedBackground)` → `.themedCard()`
- Replace `Color.green.gradient` BarMark → `.foregroundStyle(Theme.accentGradient)` — note: for Charts, use `LinearGradient` directly
- For bars exceeding the calorie goal, use a warmer gradient: `LinearGradient(colors: [Theme.calorieValue, Theme.accentGradientStart], startPoint: .bottom, endPoint: .top)` — conditionally apply based on whether `entry.calories > dailyGoal`
- Replace `.foregroundStyle(.secondary)` RuleMark → `Theme.accent.opacity(0.3)` and add `.lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))` to make it dashed per spec
- Title → `Theme.textPrimary`, avg → `Theme.textMuted`
- Axis marks → `Theme.textMuted`

- [ ] **Step 3: Theme `TopFoodsSection`**

Key changes:
- Replace `Color(.secondarySystemGroupedBackground)` → `.themedCard()`
- Medal circles: keep existing gradient colors (gold/silver/bronze look good on dark)
- Food names → `Theme.textPrimary`
- Count → `Theme.textMuted`
- Calories → `Theme.textSecondary`

- [ ] **Step 4: Theme `MealsByDaySection` and `DayMealsCard`**

Key changes:
- Replace `Color(.secondarySystemGroupedBackground)` → `.themedCard()`
- Date → `Theme.textPrimary`
- Meal count → `Theme.textMuted`
- Calorie total → `Theme.textPrimary`
- Chevron → `Theme.textMuted`
- Expanded meal rows: name → `Theme.textPrimary`, time → `Theme.textMuted`, macros → colored
- Dividers → `Color.white.opacity(0.04)`

- [ ] **Step 5: Set History background**

Add `.background(Theme.background)` to the ScrollView and `.scrollContentBackground(.hidden)`.

- [ ] **Step 6: Verify in simulator**

Build and run. History tab: gradient chart bars, themed pills, themed sections.

- [ ] **Step 7: Commit**

```bash
git add ios/NutriVisionAI/Views/HistoryView.swift
git commit -m "feat: theme History view with gradient charts and styled pills"
```

---

## Task 10: Theme Settings + Multi-Provider AI Config

**Files:**
- Modify: `ios/NutriVisionAI/Views/SettingsView.swift`

This is the second largest task. It themes the entire Settings view and replaces the AI configuration section with multi-provider cards.

- [ ] **Step 1: Theme the Form**

Add to the `NavigationStack` in SettingsView body:

```swift
.scrollContentBackground(.hidden)
.background(Theme.background)
```

And force section header colors with `.foregroundStyle()` or use the `listRowBackground` modifier for rows.

- [ ] **Step 2: Theme Account section**

- User avatar: Replace the existing name/email layout with a gradient initials circle:
  ```swift
  Circle()
      .fill(Theme.accentGradient)
      .frame(width: 36, height: 36)
      .overlay(Text(initials).font(.caption).fontWeight(.semibold).foregroundStyle(.white))
  ```
  Where `initials` = first letter of first and last name.
- "Log out" → `.foregroundStyle(Theme.destructive)`
- "Sign In" icon → `Theme.accent`

- [ ] **Step 3: Replace Analysis Provider section with multi-provider cards**

Replace the existing `analysisProviderSection` computed property with a new section. Keep the existing image analysis provider section (Backend vs Apple FM) as-is but themed. Add a **new** "AI Provider" section for LLM/chat provider selection.

Add new state:
```swift
@State private var selectedLLMProvider: String = "lmstudio"  // "lmstudio", "openai", "google", "anthropic"
@State private var showProviderSheet: ProviderSheet? = nil  // which cloud provider sheet to show

// Add this Identifiable wrapper (can be placed as a private struct inside SettingsView or at file scope):
private struct ProviderSheet: Identifiable {
    let id: String  // "openai", "google", "anthropic"
}
```

Create the provider cards section:
```swift
Section {
    // Local Server card
    providerCard(
        icon: "server.rack", iconGradient: [.blue, .cyan],
        title: "Local Server", subtitle: "LM Studio / Ollama",
        isActive: selectedLLMProvider == "lmstudio",
        action: { selectedLLMProvider = "lmstudio" }
    )

    // OpenAI card
    providerCard(
        icon: "globe", iconGradient: [.green, .mint],
        title: "OpenAI", subtitle: "GPT-4o, GPT-4o-mini",
        isActive: selectedLLMProvider == "openai",
        action: { selectedLLMProvider = "openai"; showProviderSheet = ProviderSheet(id: "openai") }
    )

    // Google card
    providerCard(
        icon: "sparkle", iconGradient: [.blue, .cyan],
        title: "Google", subtitle: "Gemini 2.5 Flash/Pro",
        isActive: selectedLLMProvider == "google",
        action: { selectedLLMProvider = "google"; showProviderSheet = ProviderSheet(id: "google") }
    )

    // Anthropic card
    providerCard(
        icon: "brain", iconGradient: [.orange, .red],
        title: "Anthropic", subtitle: "Claude Sonnet 4, Haiku",
        isActive: selectedLLMProvider == "anthropic",
        action: { selectedLLMProvider = "anthropic"; showProviderSheet = ProviderSheet(id: "anthropic") }
    )
} header: {
    Text("AI Provider")
}
```

- [ ] **Step 4: Add provider card helper and cloud provider sheet**

Add a helper function in `SettingsView`:

```swift
@ViewBuilder
private func providerCard(icon: String, iconGradient: [Color], title: String, subtitle: String, isActive: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 32, height: 32)
                .background(LinearGradient(colors: iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.accent)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }
    .listRowBackground(isActive ? Theme.accent.opacity(0.06) : Theme.cardSurface)
    .accessibilityLabel("\(title), \(subtitle), \(isActive ? "active" : "inactive")")
    .accessibilityHint("Double tap to select this provider")
}
```

Add a cloud provider detail sheet. For Google and Anthropic, show "Coming soon":

```swift
.sheet(item: $showProviderSheet) { sheet in
    CloudProviderSheet(provider: sheet.id)
}
```

Create `CloudProviderSheet` as a private struct within `SettingsView.swift`:

```swift
private struct CloudProviderSheet: View {
    let provider: String
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var selectedModel = ""
    @State private var baseURL = ""
    @State private var connectionStatus: String?

    private var isComingSoon: Bool { provider == "google" || provider == "anthropic" }

    private var models: [String] {
        switch provider {
        case "openai": return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]
        case "google": return ["gemini-2.5-flash", "gemini-2.5-pro"]
        case "anthropic": return ["claude-sonnet-4-20250514", "claude-haiku-4-5-20251001"]
        default: return []
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isComingSoon {
                    Section {
                        Text("Coming soon — requires backend support for this provider.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Section("API Key") {
                    SecureField("Enter API key", text: $apiKey)
                        .onAppear { apiKey = KeychainHelper.read(key: "\(provider)_api_key") ?? "" }
                }

                Section("Model") {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(models, id: \.self) { Text($0) }
                    }
                }

                Section("Base URL (Optional)") {
                    TextField("https://api.openai.com/v1", text: $baseURL)
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onAppear { baseURL = UserDefaults.standard.string(forKey: "\(provider)_base_url") ?? "" }
                }

                Section {
                    GradientButton(title: isComingSoon ? "Save Key for Later" : "Save & Activate") {
                        if !apiKey.isEmpty {
                            try? KeychainHelper.save(key: "\(provider)_api_key", value: apiKey)
                        }
                        if !baseURL.isEmpty {
                            UserDefaults.standard.set(baseURL, forKey: "\(provider)_base_url")
                        }
                        dismiss()
                    }

                    // Note: Tests backend connectivity, not provider-specific API key validation.
                    // Provider-specific validation will be added when backend gains Google/Anthropic support.
                    Button {
                        Task {
                            connectionStatus = "Testing..."
                            do {
                                _ = try await APIClient.shared.get("/settings") as SettingsResponse
                                connectionStatus = "Connected"
                            } catch {
                                connectionStatus = "Failed: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Test Connection")
                            Spacer()
                            if let status = connectionStatus {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(status == "Connected" ? Theme.successStart : Theme.destructive)
                            }
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(provider.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Theme remaining Settings sections**

- Nutrition Goals rows: `listRowBackground(Theme.cardSurface)`, labels → `Theme.textPrimary`, values → `Theme.textSecondary`
- LM Studio config rows: same treatment
- Connection row: same treatment
- Save button: replace with `GradientButton`
- About/Version: theme
- Success toast: keep `.ultraThinMaterial`
- Login sheet: theme Form background, add `GradientButton` for Sign In
- Server URL sheet: theme Form background

- [ ] **Step 6: Verify in simulator**

Build and run. Settings tab: dark Form, violet section headers, provider cards, cloud provider sheets.

- [ ] **Step 7: Commit**

```bash
git add ios/NutriVisionAI/Views/SettingsView.swift
git commit -m "feat: theme Settings, add multi-provider AI config with provider cards"
```

---

## Task 11: Final Polish + Verification

**Files:**
- All views (minor adjustments)

- [ ] **Step 1: Add `.superpowers/` to `.gitignore`**

Check if `.superpowers/` is in `.gitignore`. If not, add it:

```bash
echo ".superpowers/" >> .gitignore
```

- [ ] **Step 2: Full visual walkthrough**

Build and run on iPhone 15 Pro simulator. Walk through all 5 tabs:
1. Dashboard: calorie ring glow, gradient macros, themed meals, AI suggestions
2. Scan: themed capture, themed results with portion selectors, quick search
3. Log: themed search, portion controls in builder, themed AI lookup
4. History: gradient chart, styled pills, themed sections
5. Settings: dark form, provider cards, cloud sheets

- [ ] **Step 3: Test edge states**

- Empty dashboard (no meals)
- Scan with no image
- Log with empty search
- History with no data
- Settings with no logged-in user

- [ ] **Step 4: Fix any visual inconsistencies found**

Address any remaining `Color(.secondarySystemGroupedBackground)` or `Color(.systemGray5)` references that were missed.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: final polish and visual consistency pass"
```

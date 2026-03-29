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
        let hour = AppTimeZone.currentHour()
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
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
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
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
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
        }
        .animation(.easeIn(duration: 0.3), value: suggestions.count)
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
        .background(Theme.cardSurface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
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

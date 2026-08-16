import SwiftUI

struct AILookupFlowView: View {
    @EnvironmentObject private var draftStore: MealDraftStore

    @State private var query = ""
    @State private var isLoading = false
    @State private var result: AIFoodResult?
    @State private var errorMessage: String?
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 8)

                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 20)

                Text("AI Food Lookup")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)

                Text("Describe any food for an AI nutrition estimate")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Query input
                VStack(spacing: 12) {
                    TextField("e.g., pad thai, homemade pizza, acai bowl", text: $query)
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Theme.textPrimary)
                        .submitLabel(.search)
                        .onSubmit { lookupFood() }

                    GradientButton(
                        title: "Ask AI",
                        icon: "sparkles",
                        isLoading: isLoading,
                        isDisabled: query.trimmingCharacters(in: .whitespaces).isEmpty,
                        action: { lookupFood() }
                    )
                }
                .padding(.horizontal, 24)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.destructive)
                        .padding(.horizontal)
                }

                // Result card
                if let result = result {
                    AIFoodResultCard(result: result, onAdd: {
                        addResultToMeal(result)
                    })
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
        }
        .background(Theme.background)
        .overlay(alignment: .top) {
            if let message = toastMessage {
                toastView(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Actions

    private func lookupFood() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response: AIFoodResult
                if FoodAnalysisService.shared.isCloudMode {
                    response = try await cloudAILookup(query: trimmed)
                } else {
                    response = try await APIClient.shared.aiLookup(query: trimmed)
                }
                await MainActor.run {
                    result = response
                    isLoading = false
                }
            } catch {
                if !(error is CancellationError) {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isLoading = false
                    }
                }
            }
        }
    }

    private func addResultToMeal(_ result: AIFoodResult) {
        let item = MealDraftItem.from(aiResult: result)
        draftStore.addItem(item)
        showToast("\(result.foodName.capitalized) added!")

        // Reset for next query
        query = ""
        self.result = nil
        errorMessage = nil
    }

    private func cloudAILookup(query: String) async throws -> AIFoodResult {
        let prompt = """
        You are a nutrition expert. Estimate the nutrition for a typical serving of the given food.
        For composite dishes (chia seed pudding, biryani, pad thai), estimate the complete dish.
        For individual items (chicken breast, rice), estimate per standard serving.

        Return ONLY JSON: {"food_name":"...","serving_grams":150.0,"calories":250.0,"protein_g":10.0,"carbs_g":30.0,"fat_g":8.0,"confidence":0.8,"notes":"brief note about estimate"}
        """

        let responseText = try await FoodAnalysisService.shared.chatCompletion(
            prompt: prompt,
            userMessage: query
        )

        // Parse JSON — handle markdown fences
        var text = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            if let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
            if text.hasSuffix("```") { text = String(text.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            throw AnalysisError.parsingFailed("No JSON in AI response")
        }
        let jsonStr = String(text[start...end])
        guard let data = jsonStr.data(using: .utf8) else {
            throw AnalysisError.parsingFailed("Invalid JSON encoding")
        }

        return try JSONDecoder().decode(AIFoodResult.self, from: data)
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.successStart)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .padding(.top, 8)
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(duration: 0.3)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                toastMessage = nil
            }
        }
    }
}

// MARK: - AI Food Result Card

struct AIFoodResultCard: View {
    let result: AIFoodResult
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accent)
                Text("AI Estimate")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let confidence = result.confidence {
                    Text("\(Int(confidence * 100))% confidence")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            VStack(spacing: 8) {
                Text(result.foodName.capitalized)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Text("\(Int(result.servingGrams))g serving")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 16) {
                NutritionMiniStat(value: Int(result.calories), label: "Cal")
                NutritionMiniStat(value: Int(result.proteinG), label: "Protein", unit: "g")
                NutritionMiniStat(value: Int(result.carbsG), label: "Carbs", unit: "g")
                NutritionMiniStat(value: Int(result.fatG), label: "Fat", unit: "g")
            }

            if let notes = result.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
            }

            GradientButton(title: "Add to Meal", icon: "plus.circle.fill", action: onAdd)
        }
        .padding()
        .themedCard()
    }
}

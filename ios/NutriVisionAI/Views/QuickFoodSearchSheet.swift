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
                        .autocorrectionDisabled()
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
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    results = []
                    return
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                search()
            }
        }
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        if FoodAnalysisService.shared.isCloudMode {
            // Local DB search — instant, no network needed
            results = NutritionDB.shared.search(query: trimmed)
        } else {
            isSearching = true
            Task {
                do {
                    let response = try await APIClient.shared.searchFoods(query: trimmed)
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

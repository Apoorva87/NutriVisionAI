import SwiftUI

struct LogView: View {
    @State private var searchQuery = ""
    @State private var searchResults: [FoodItem] = []
    @State private var customFoods: [CustomFood] = []
    @State private var mealBuilder: [MealBuilderItem] = []
    @State private var mealName = ""
    @State private var isSearching = false
    @State private var isLoadingCustomFoods = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false
    @State private var showAILookup = false
    @State private var selectedTab = 0 // 0 = Search, 1 = Custom Foods

    private var totalCalories: Double {
        mealBuilder.reduce(0) { $0 + $1.totalCalories }
    }

    private var totalProtein: Double {
        mealBuilder.reduce(0) { $0 + $1.totalProtein }
    }

    private var totalCarbs: Double {
        mealBuilder.reduce(0) { $0 + $1.totalCarbs }
    }

    private var totalFat: Double {
        mealBuilder.reduce(0) { $0 + $1.totalFat }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Meal builder summary (if items added)
                if !mealBuilder.isEmpty {
                    MealBuilderSummary(
                        items: $mealBuilder,
                        totalCalories: totalCalories,
                        totalProtein: totalProtein,
                        totalCarbs: totalCarbs,
                        totalFat: totalFat,
                        mealName: $mealName,
                        onRemoveItem: removeItem,
                        onSave: saveMeal,
                        onClear: clearBuilder,
                        isSaving: isSaving
                    )
                }

                // Tab picker
                Picker("Source", selection: $selectedTab) {
                    Text("Search").tag(0)
                    Text("My Foods").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    // Food search
                    FoodSearchSection(
                        searchQuery: $searchQuery,
                        searchResults: searchResults,
                        isSearching: isSearching,
                        onSearch: performSearch,
                        onSelect: addToMeal,
                        onAILookup: { showAILookup = true }
                    )
                } else {
                    // Custom foods
                    CustomFoodsSection(
                        customFoods: customFoods,
                        isLoading: isLoadingCustomFoods,
                        onSelect: addCustomFoodToMeal,
                        onRefresh: loadCustomFoods
                    )
                }
            }
            .background(Theme.background)
            .navigationTitle("Log Meal")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                if !mealBuilder.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
                            clearBuilder()
                        }
                    }
                }
            }
            .task {
                await loadCustomFoods()
            }
            .alert("Meal Saved", isPresented: $showSuccessAlert) {
                Button("OK") { }
            } message: {
                Text("Your meal has been logged successfully.")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showAILookup) {
                AIFoodLookupSheet(onAddFood: { item in
                    addToMeal(item)
                    showAILookup = false
                })
            }
        }
    }

    private func performSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        if FoodAnalysisService.shared.isCloudMode {
            // Local DB search — instant, no async needed
            searchResults = NutritionDB.shared.search(query: trimmed)
        } else {
            isSearching = true
            Task {
                do {
                    let response = try await APIClient.shared.searchFoods(query: searchQuery)
                    await MainActor.run {
                        searchResults = response.items
                        isSearching = false
                    }
                } catch {
                    await MainActor.run {
                        searchResults = []
                        isSearching = false
                    }
                }
            }
        }
    }

    private func loadCustomFoods() async {
        isLoadingCustomFoods = true
        do {
            let response = try await APIClient.shared.customFoods()
            customFoods = response["items"] ?? []
        } catch {
            customFoods = []
        }
        isLoadingCustomFoods = false
    }

    private func addToMeal(_ food: FoodItem) {
        let item = MealBuilderItem(
            id: UUID(),
            canonicalName: food.canonicalName,
            displayName: food.canonicalName.capitalized,
            baseGrams: food.servingGrams,
            caloriesPer100g: food.calories / food.servingGrams * 100,
            proteinPer100g: food.proteinG / food.servingGrams * 100,
            carbsPer100g: food.carbsG / food.servingGrams * 100,
            fatPer100g: food.fatG / food.servingGrams * 100
        )
        mealBuilder.append(item)
    }

    private func addCustomFoodToMeal(_ food: CustomFood) {
        let item = MealBuilderItem(
            id: UUID(),
            canonicalName: food.foodName.lowercased(),
            displayName: food.foodName.capitalized,
            baseGrams: food.servingGrams,
            caloriesPer100g: food.calories / food.servingGrams * 100,
            proteinPer100g: food.proteinG / food.servingGrams * 100,
            carbsPer100g: food.carbsG / food.servingGrams * 100,
            fatPer100g: food.fatG / food.servingGrams * 100
        )
        mealBuilder.append(item)
    }

    private func removeItem(_ item: MealBuilderItem) {
        mealBuilder.removeAll { $0.id == item.id }
    }

    private func clearBuilder() {
        mealBuilder = []
        mealName = ""
    }

    private func saveMeal() {
        guard !mealBuilder.isEmpty else { return }

        isSaving = true

        if FoodAnalysisService.shared.isCloudMode {
            // Cloud mode: save locally using AnalysisItem
            let analysisItems = mealBuilder.map { item in
                AnalysisItem(
                    detectedName: item.displayName,
                    canonicalName: item.canonicalName,
                    portionLabel: "custom",
                    estimatedGrams: item.grams,
                    uncertainty: "low",
                    confidence: 1.0,
                    calories: item.totalCalories,
                    proteinG: item.totalProtein,
                    carbsG: item.totalCarbs,
                    fatG: item.totalFat,
                    visionConfidence: 1.0,
                    dbMatch: true,
                    nutritionAvailable: true
                )
            }
            let _ = LocalMealStore.shared.saveMeal(
                name: mealName.isEmpty ? "Quick Log" : mealName,
                image: nil,
                items: analysisItems
            )
            isSaving = false
            showSuccessAlert = true
            clearBuilder()
        } else {
            // Backend mode
            let items = mealBuilder.map { item -> MealItemInput in
                MealItemInput(
                    detectedName: item.displayName,
                    canonicalName: item.canonicalName,
                    portionLabel: "custom",
                    estimatedGrams: item.grams,
                    uncertainty: "low",
                    confidence: 1.0
                )
            }

            let request = CreateMealRequest(
                mealName: mealName.isEmpty ? "Quick Log" : mealName,
                imagePath: nil,
                items: items
            )

            Task {
                do {
                    _ = try await APIClient.shared.createMeal(request)
                    await MainActor.run {
                        isSaving = false
                        showSuccessAlert = true
                        clearBuilder()
                    }
                } catch {
                    await MainActor.run {
                        isSaving = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - Meal Builder Item

struct MealBuilderItem: Identifiable {
    let id: UUID
    let canonicalName: String
    let displayName: String
    var gramsMultiplier: Double = 1.0
    let baseGrams: Double
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double

    var grams: Double { baseGrams * gramsMultiplier }
    var totalCalories: Double { grams * caloriesPer100g / 100 }
    var totalProtein: Double { grams * proteinPer100g / 100 }
    var totalCarbs: Double { grams * carbsPer100g / 100 }
    var totalFat: Double { grams * fatPer100g / 100 }
}

// MARK: - Meal Builder Summary

struct MealBuilderSummary: View {
    @Binding var items: [MealBuilderItem]
    let totalCalories: Double
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    @Binding var mealName: String
    let onRemoveItem: (MealBuilderItem) -> Void
    let onSave: () -> Void
    let onClear: () -> Void
    let isSaving: Bool

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Building Meal")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(items.count) item\(items.count == 1 ? "" : "s") - \(Int(totalCalories)) cal")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.textMuted)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()

                // Meal name
                TextField("Meal name (optional)", text: $mealName)
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                // Items list
                ForEach($items) { $item in
                    MealBuilderItemRow(item: $item, onRemove: { onRemoveItem(item) })
                }

                // Totals
                HStack(spacing: 16) {
                    NutritionMiniStat(value: Int(totalCalories), label: "Cal")
                    NutritionMiniStat(value: Int(totalProtein), label: "P", unit: "g")
                    NutritionMiniStat(value: Int(totalCarbs), label: "C", unit: "g")
                    NutritionMiniStat(value: Int(totalFat), label: "F", unit: "g")

                    Spacer()

                    Button(action: onSave) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Theme.accentGradient)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .disabled(isSaving)
                }
                .padding()
            }
        }
        .themedCard(glow: true)
    }
}

struct MealBuilderItemRow: View {
    @Binding var item: MealBuilderItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Theme.destructive)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Int(item.grams))g")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                Text("\(Int(item.totalCalories)) cal")
                    .font(.subheadline)
                    .foregroundStyle(Theme.calorieValue)
            }

            PortionSelector(
                baseGrams: item.baseGrams,
                selectedMultiplier: $item.gramsMultiplier
            )
            .padding(.leading, 22)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct NutritionMiniStat: View {
    let value: Int
    let label: String
    var unit: String = ""

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 1) {
                Text("\(value)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Food Search Section

struct FoodSearchSection: View {
    @Binding var searchQuery: String
    let searchResults: [FoodItem]
    let isSearching: Bool
    let onSearch: () -> Void
    let onSelect: (FoodItem) -> Void
    let onAILookup: () -> Void

    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textMuted)
                    TextField("Search foods...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                        .submitLabel(.search)
                        .onSubmit(onSearch)
                        .onChange(of: searchQuery) { _ in
                            debounceTask?.cancel()
                            debounceTask = Task {
                                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
                                guard !Task.isCancelled else { return }
                                await MainActor.run { onSearch() }
                            }
                        }

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.cardBorder)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding()

            Divider()

            // Results
            if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("No foods found for \"\(searchQuery)\"")
                    }

                    Button {
                        onAILookup()
                    } label: {
                        Label("Ask AI for nutrition info", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textSecondary)

                    Text("Search for Foods")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Search our database or use AI to find nutrition info for any food")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        onAILookup()
                    } label: {
                        Label("AI Food Lookup", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(searchResults) { food in
                    FoodSearchResultRow(food: food)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(food) }
                        .listRowBackground(Theme.cardSurface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

struct FoodSearchResultRow: View {
    let food: FoodItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(food.canonicalName.capitalized)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 8) {
                    Text("\(Int(food.servingGrams))g serving")
                    if let source = food.sourceLabel {
                        Text("(\(source))")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(food.calories)) cal")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 6) {
                    Text("P:\(Int(food.proteinG))")
                        .foregroundStyle(Theme.proteinColor)
                    Text("C:\(Int(food.carbsG))")
                        .foregroundStyle(Theme.carbsColor)
                    Text("F:\(Int(food.fatG))")
                        .foregroundStyle(Theme.fatColor)
                }
                .font(.caption2)
            }

            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Theme.successStart)
                .font(.title3)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Custom Foods Section

struct CustomFoodsSection: View {
    let customFoods: [CustomFood]
    let isLoading: Bool
    let onSelect: (CustomFood) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        if isLoading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if customFoods.isEmpty {
            ContentUnavailableView {
                Label("No Custom Foods", systemImage: "star")
            } description: {
                Text("Custom foods you create will appear here")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(customFoods) { food in
                CustomFoodRow(food: food)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(food) }
                    .listRowBackground(Theme.cardSurface)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await onRefresh()
            }
        }
    }
}

struct CustomFoodRow: View {
    let food: CustomFood

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(food.foodName.capitalized)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)

                Text("\(Int(food.servingGrams))g serving")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(food.calories)) cal")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 6) {
                    Text("P:\(Int(food.proteinG))")
                        .foregroundStyle(Theme.proteinColor)
                    Text("C:\(Int(food.carbsG))")
                        .foregroundStyle(Theme.carbsColor)
                    Text("F:\(Int(food.fatG))")
                        .foregroundStyle(Theme.fatColor)
                }
                .font(.caption2)
            }

            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Theme.successStart)
                .font(.title3)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AI Food Lookup Sheet

struct AIFoodLookupSheet: View {
    let onAddFood: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isLoading = false
    @State private var result: AIFoodResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Query input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What food do you want nutrition info for?")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)

                        TextField("e.g., pad thai, homemade pizza, acai bowl", text: $query)
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Theme.textPrimary)

                        GradientButton(
                            title: "Ask AI",
                            icon: "sparkles",
                            isLoading: isLoading,
                            isDisabled: query.isEmpty,
                            action: { lookupFood() }
                        )
                    }
                    .padding()

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.destructive)
                            .padding(.horizontal)
                    }

                    // Result
                    if let result = result {
                        AIFoodResultCard(result: result, onAdd: {
                            let food = FoodItem(
                                canonicalName: result.foodName.lowercased(),
                                servingGrams: result.servingGrams,
                                calories: result.calories,
                                proteinG: result.proteinG,
                                carbsG: result.carbsG,
                                fatG: result.fatG,
                                sourceLabel: "AI Estimate"
                            )
                            onAddFood(food)
                        })
                        .padding(.horizontal)
                    }

                    Spacer()
                }
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("AI Food Lookup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func lookupFood() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await APIClient.shared.aiLookup(query: query)
                await MainActor.run {
                    result = response
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

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

#Preview {
    LogView()
}

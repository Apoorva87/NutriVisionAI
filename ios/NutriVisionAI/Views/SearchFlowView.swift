import SwiftUI

struct SearchFlowView: View {
    @EnvironmentObject private var draftStore: MealDraftStore

    @State private var searchQuery = ""
    @State private var searchResults: [FoodItem] = []
    @State private var customFoods: [CustomFood] = []
    @State private var isSearching = false
    @State private var isLoadingCustomFoods = false
    @State private var selectedTab = 0 // 0 = Search, 1 = Custom Foods
    @State private var toastMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Source", selection: $selectedTab) {
                Text("Search").tag(0)
                Text("My Foods").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == 0 {
                FoodSearchSection(
                    searchQuery: $searchQuery,
                    searchResults: searchResults,
                    isSearching: isSearching,
                    onSearch: performSearch,
                    onSelect: addFoodToMeal
                )
            } else {
                CustomFoodsSection(
                    customFoods: customFoods,
                    isLoading: isLoadingCustomFoods,
                    onSelect: addCustomFoodToMeal,
                    onRefresh: loadCustomFoods
                )
            }
        }
        .background(Theme.background)
        .task {
            await loadCustomFoods()
        }
        .task(id: searchQuery) {
            let query = searchQuery.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else {
                searchResults = []
                return
            }
            // Debounce 300ms — task auto-cancels if searchQuery changes
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            if FoodAnalysisService.shared.isCloudMode {
                searchResults = NutritionDB.shared.search(query: query)
            } else {
                isSearching = true
                do {
                    let response = try await APIClient.shared.searchFoods(query: query)
                    if !Task.isCancelled {
                        searchResults = response.items
                    }
                } catch {
                    if !Task.isCancelled {
                        searchResults = []
                    }
                }
                isSearching = false
            }
        }
        .overlay(alignment: .top) {
            if let message = toastMessage {
                toastView(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Actions

    private func addFoodToMeal(_ food: FoodItem) {
        let item = MealDraftItem.from(foodItem: food)
        draftStore.addItem(item)
        showToast("\(food.canonicalName.capitalized) added!")
    }

    private func addCustomFoodToMeal(_ food: CustomFood) {
        let item = MealDraftItem.from(customFood: food)
        draftStore.addItem(item)
        showToast("\(food.foodName.capitalized) added!")
    }

    private func performSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        if FoodAnalysisService.shared.isCloudMode {
            searchResults = NutritionDB.shared.search(query: trimmed)
        } else {
            isSearching = true
            Task {
                do {
                    let response = try await APIClient.shared.searchFoods(query: trimmed)
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
        if FoodAnalysisService.shared.isCloudMode {
            customFoods = await LocalMealStore.shared.allCustomFoods()
        } else {
            do {
                let response = try await APIClient.shared.customFoods()
                customFoods = response["items"] ?? []
            } catch {
                customFoods = []
            }
        }
        isLoadingCustomFoods = false
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

// MARK: - Food Search Section

struct FoodSearchSection: View {
    @Binding var searchQuery: String
    let searchResults: [FoodItem]
    let isSearching: Bool
    let onSearch: () -> Void
    let onSelect: (FoodItem) -> Void

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
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(onSearch)

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
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No foods found for \"\(searchQuery)\"")
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

                    Text("Search our database to find nutrition info for any food")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
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

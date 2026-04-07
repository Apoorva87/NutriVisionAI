import SwiftUI

struct GroceryListView: View {
    // Static cache so suggestions survive navigation pop/push within a session
    private static var cachedSuggestions: [GroceryAISuggestion] = []

    @State private var suggestions: [GroceryAISuggestion] = GroceryListView.cachedSuggestions
    @State private var cartItems: [GroceryCartItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var preferenceInput = ""
    @State private var customItemName = ""
    @State private var customItemQty = ""
    @State private var addedItemNames: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Cart Section (top — user's active list)
                    cartSection

                    // AI Suggestions Section (below — reference/add from)
                    aiSuggestionsSection
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Grocery List")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .onAppear { reloadCart() }
        }
    }

    // MARK: - AI Suggestions

    private var aiSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Suggestions", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    Task { await generateList() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Theme.textMuted)
                }
            }

            // Preference input
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundStyle(Theme.textMuted)
                    .font(.caption)
                TextField("Indian Vegetarian", text: $preferenceInput)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit { Task { await generateList() } }
            }
            .padding(8)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    ShimmerRect()
                }
            } else if let error = errorMessage {
                VStack(spacing: 6) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.destructive)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if suggestions.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Tap refresh to generate a weekly grocery list")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ForEach(suggestions) { item in
                    SuggestionRow(
                        item: item,
                        isAdded: addedItemNames.contains(item.item.lowercased())
                    ) {
                        addToCart(item)
                    }
                }
            }
        }
        .padding()
        .themedCard()
        .task {
            if suggestions.isEmpty {
                await generateList()
            }
        }
    }

    // MARK: - Cart

    private var cartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("My Cart", systemImage: "cart.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                if !cartItems.isEmpty {
                    Text("\(cartItems.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }

                Spacer()

                if !cartItems.isEmpty {
                    Menu {
                        Button("Clear Checked", role: .destructive) {
                            GroceryCartStore.shared.clearChecked()
                            reloadCart()
                        }
                        Button("Clear All", role: .destructive) {
                            GroceryCartStore.shared.clearAll()
                            reloadCart()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(Theme.destructive)
                    }
                }
            }

            // Custom item input
            HStack(spacing: 8) {
                TextField("Item name", text: $customItemName)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                TextField("Qty", text: $customItemQty)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 60)
                Button {
                    addCustomItem()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .disabled(customItemName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if cartItems.isEmpty {
                HStack {
                    Spacer()
                    Text("Cart is empty")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ForEach(cartItems) { item in
                    CartRow(item: item) {
                        GroceryCartStore.shared.toggleChecked(id: item.id)
                        reloadCart()
                    } onDelete: {
                        GroceryCartStore.shared.removeItem(id: item.id)
                        reloadCart()
                    }
                }
            }
        }
        .padding()
        .themedCard()
    }

    // MARK: - Actions

    private func generateList() async {
        isLoading = true
        errorMessage = nil

        let calorieGoal = UserDefaults.standard.integer(forKey: "local_calorie_goal")
        let budget = calorieGoal > 0 ? calorieGoal : 2200
        let preference = preferenceInput.isEmpty ? "Indian Vegetarian" : preferenceInput

        let prompt = """
        You are a nutrition-aware grocery planner. Generate a weekly grocery list for 1 person \
        with a daily calorie budget of \(budget) calories.
        Cuisine preference: \(preference).

        For each item, provide the item name, quantity needed for 1 week, and brief keyword hints \
        (2-3 meal names this item is used in).

        Return ONLY a JSON array:
        [{"item": "basmati rice", "quantity": "2 lb", "hints": "biryani, pulao, khichdi"}, ...]

        Include 15-25 items covering: proteins, grains/lentils, vegetables, fruits, dairy, and pantry staples.
        Keep quantities practical for 1 person for 1 week.
        """

        do {
            let content = try await FoodAnalysisService.shared.chatCompletion(
                prompt: prompt,
                userMessage: "Generate the grocery list now."
            )
            if let jsonStart = content.firstIndex(of: "["),
               let jsonEnd = content.lastIndex(of: "]") {
                let jsonString = String(content[jsonStart...jsonEnd])
                if let data = jsonString.data(using: .utf8) {
                    let decoded = try JSONDecoder().decode([GroceryAISuggestion].self, from: data)
                    suggestions = sortedSuggestions(decoded)
                    Self.cachedSuggestions = suggestions
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func addToCart(_ item: GroceryAISuggestion) {
        GroceryCartStore.shared.addItem(name: item.item, quantity: item.quantity, hints: item.hints)
        addedItemNames.insert(item.item.lowercased())
        reloadCart()
    }

    private func addCustomItem() {
        let name = customItemName.trimmingCharacters(in: .whitespaces)
        let qty = customItemQty.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        GroceryCartStore.shared.addItem(name: name, quantity: qty.isEmpty ? "1" : qty, isCustom: true)
        customItemName = ""
        customItemQty = ""
        reloadCart()
    }

    private static let bulkKeywords: Set<String> = [
        "rice", "wheat", "flour", "atta", "oil", "sugar", "salt", "ghee",
        "lentil", "dal", "daal", "chana", "moong", "toor", "urad", "masoor",
        "rajma", "chickpea", "bean", "pasta", "noodle", "oat", "cereal",
        "bread", "maida", "semolina", "sooji", "rava", "poha", "quinoa"
    ]

    private func sortedSuggestions(_ items: [GroceryAISuggestion]) -> [GroceryAISuggestion] {
        items.sorted { a, b in
            let aIsBulk = isBulkItem(a.item)
            let bIsBulk = isBulkItem(b.item)
            if aIsBulk != bIsBulk { return !aIsBulk }
            return false // preserve original order within each group
        }
    }

    private func isBulkItem(_ name: String) -> Bool {
        let lower = name.lowercased()
        return Self.bulkKeywords.contains { lower.contains($0) }
    }

    private func reloadCart() {
        cartItems = GroceryCartStore.shared.allItems()
        addedItemNames = Set(cartItems.map { $0.name.lowercased() })
    }
}

// MARK: - Sub-views

private struct SuggestionRow: View {
    let item: GroceryAISuggestion
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.item)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isAdded ? Theme.textMuted : Theme.textPrimary)
                HStack(spacing: 6) {
                    Text(item.quantity)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if !item.hints.isEmpty {
                        Text("(\(item.hints))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isAdded ? .green : Theme.accent)
            }
            .disabled(isAdded)
        }
        .padding(.vertical, 4)
    }
}

private struct CartRow: View {
    let item: GroceryCartItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : Theme.textMuted)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(item.isChecked ? Theme.textMuted : Theme.textPrimary)
                        .strikethrough(item.isChecked)
                    if item.isCustom {
                        Text("custom")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.15))
                            .foregroundStyle(Theme.accent)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(item.quantity)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if !item.hints.isEmpty {
                        Text("(\(item.hints))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShimmerRect: View {
    @State private var shimmer = false
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(shimmer ? 0.06 : 0.02))
            .frame(height: 44)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: shimmer)
            .onAppear { shimmer = true }
    }
}

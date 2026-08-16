import SwiftUI

struct MealDraftReviewSheet: View {
    @EnvironmentObject private var draftStore: MealDraftStore
    @Environment(\.dismiss) private var dismiss

    @State private var showSaveSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Meal name
                    TextField("Meal name (optional)", text: $draftStore.mealName)
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal)

                    // Nutrition summary
                    NutritionSummaryBanner(
                        calories: draftStore.totalCalories,
                        protein: draftStore.totalProtein,
                        carbs: draftStore.totalCarbs,
                        fat: draftStore.totalFat
                    )

                    // Items list
                    VStack(spacing: 0) {
                        ForEach(draftStore.items) { item in
                            DraftItemRow(
                                item: draftStore.binding(for: item.id),
                                onRemove: { draftStore.removeItem(id: item.id) }
                            )

                            if item.id != draftStore.items.last?.id {
                                Divider().padding(.horizontal)
                            }
                        }
                    }
                    .themedCard()

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.destructive)
                            .padding(.horizontal)
                    }

                    // Save button
                    GradientButton(
                        title: "Save Meal",
                        icon: "checkmark.circle.fill",
                        isLoading: draftStore.isSaving,
                        isDisabled: draftStore.includedItems.isEmpty,
                        action: saveMeal
                    )
                    .padding(.horizontal)

                    // Add more button
                    Button {
                        dismiss()
                    } label: {
                        Label("Add More Items", systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.bottom, 16)
                }
                .padding(.top, 8)
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Review Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear All", role: .destructive) {
                        draftStore.clear()
                        dismiss()
                    }
                    .foregroundStyle(Theme.destructive)
                }
            }
            .alert("Meal Saved", isPresented: $showSaveSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your meal has been logged successfully.")
            }
        }
    }

    private func saveMeal() {
        Task {
            do {
                try await draftStore.saveMeal()
                showSaveSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Draft Item Row

struct DraftItemRow: View {
    @Binding var item: MealDraftItem
    let onRemove: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 12) {
                // Include/exclude toggle
                Button {
                    withAnimation { item.isIncluded.toggle() }
                } label: {
                    Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isIncluded ? Theme.successStart : Theme.textMuted)
                        .font(.title3)
                }

                // Provenance badge
                Image(systemName: item.provenance.systemImage)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(item.isIncluded ? Theme.textPrimary : Theme.textMuted)
                    Text("\(Int(item.grams))g")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                Text("\(Int(item.totalCalories)) cal")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(item.isIncluded ? Theme.calorieValue : Theme.textMuted)

                // Expand/collapse
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }

            if isExpanded && item.isIncluded {
                // Portion selector
                PortionSelector(
                    baseGrams: item.baseGrams,
                    selectedMultiplier: $item.gramsMultiplier,
                    overrideGrams: $item.overrideGrams
                )
                .padding(.leading, 36)

                // Macro summary
                HStack(spacing: 12) {
                    MacroChip(label: "P", value: Int(item.totalProtein), color: Theme.proteinColor)
                    MacroChip(label: "C", value: Int(item.totalCarbs), color: Theme.carbsColor)
                    MacroChip(label: "F", value: Int(item.totalFat), color: Theme.fatColor)
                }
                .padding(.leading, 36)

                // Remove button
                Button(role: .destructive) {
                    withAnimation { onRemove() }
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(Theme.destructive)
                }
                .padding(.leading, 36)
            }
        }
        .padding()
        .opacity(item.isIncluded ? 1.0 : 0.6)
    }
}

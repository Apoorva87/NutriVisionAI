// BarcodeResultSheet — Shows product nutrition from barcode scan with add/save options.

import SwiftUI

struct BarcodeResultSheet: View {
    let product: OpenFoodFactsProduct
    let onAddToMeal: (EditableAnalysisItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var servingGrams: Double = 100.0
    @State private var gramsText: String = "100"
    @State private var showSavedConfirmation = false

    private var scale: Double { servingGrams / 100.0 }
    private var calories: Double { product.caloriesPer100g * scale }
    private var protein: Double { product.proteinPer100g * scale }
    private var carbs: Double { product.carbsPer100g * scale }
    private var fat: Double { product.fatPer100g * scale }

    private var hasIncompleteData: Bool {
        product.caloriesPer100g == 0 && product.proteinPer100g == 0 &&
        product.carbsPer100g == 0 && product.fatPer100g == 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Product header
                    VStack(spacing: 8) {
                        Image(systemName: "barcode")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.accent)

                        Text(product.productName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)

                        if !product.brands.isEmpty {
                            Text(product.brands)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Text(product.barcode)
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                            .monospaced()
                    }
                    .padding()

                    // Incomplete data warning
                    if hasIncompleteData {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Nutrition data not available for this product")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                    }

                    // Nutrition banner (reuses same layout as AnalyzeView)
                    HStack(spacing: 0) {
                        BarcodeNutrientItem(value: Int(calories), label: "Cal", color: Theme.calorieValue)
                        Divider().frame(height: 40)
                        BarcodeNutrientItem(value: Int(protein), label: "Protein", unit: "g", color: Theme.proteinColor)
                        Divider().frame(height: 40)
                        BarcodeNutrientItem(value: Int(carbs), label: "Carbs", unit: "g", color: Theme.carbsColor)
                        Divider().frame(height: 40)
                        BarcodeNutrientItem(value: Int(fat), label: "Fat", unit: "g", color: Theme.fatColor)
                    }
                    .padding(.vertical, 12)
                    .background(Theme.accent.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.12)))
                    .padding(.horizontal)

                    // Per 100g reference
                    if !hasIncompleteData {
                        HStack(spacing: 16) {
                            Text("Per 100g:")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                            Text("\(Int(product.caloriesPer100g)) cal")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Text("P:\(Int(product.proteinPer100g))g")
                                .font(.caption)
                                .foregroundStyle(Theme.proteinColor)
                            Text("C:\(Int(product.carbsPer100g))g")
                                .font(.caption)
                                .foregroundStyle(Theme.carbsColor)
                            Text("F:\(Int(product.fatPer100g))g")
                                .font(.caption)
                                .foregroundStyle(Theme.fatColor)
                        }
                    }

                    // Serving size adjustment
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Serving Size")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textPrimary)

                        if let servingStr = product.servingSizeString, !servingStr.isEmpty {
                            Text("Package says: \(servingStr)")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }

                        HStack(spacing: 12) {
                            // Quick presets
                            ForEach([50, 100, 150, 200], id: \.self) { g in
                                Button {
                                    servingGrams = Double(g)
                                    gramsText = "\(g)"
                                } label: {
                                    Text("\(g)g")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Int(servingGrams) == g ? Theme.accent.opacity(0.12) : Color.white.opacity(0.04))
                                        .foregroundStyle(Int(servingGrams) == g ? Theme.accent : Theme.textSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Int(servingGrams) == g ? Theme.accent.opacity(0.3) : Theme.cardBorder)
                                        )
                                }
                            }

                            Spacer()

                            // Editable gram field
                            HStack(spacing: 4) {
                                TextField("g", text: $gramsText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(width: 50)
                                    .onChange(of: gramsText) { _, newValue in
                                        if let g = Double(newValue), g > 0 {
                                            servingGrams = g
                                        }
                                    }
                                Text("g")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.cardBorder))
                        }
                    }
                    .padding()
                    .themedCard()
                    .padding(.horizontal)

                    // Action buttons
                    VStack(spacing: 12) {
                        GradientButton(
                            title: "Add to Meal",
                            icon: "plus.circle.fill",
                            isDisabled: hasIncompleteData,
                            action: addToMeal
                        )

                        Button {
                            saveAsCustomFood()
                        } label: {
                            Label("Save as Custom Food", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.cardSurface)
                                .foregroundStyle(Theme.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(Theme.background)
            .navigationTitle("Scanned Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .overlay {
                if showSavedConfirmation {
                    Text("Saved to Custom Foods!")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.successStart)
                        .clipShape(Capsule())
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { showSavedConfirmation = false }
                            }
                        }
                }
            }
        }
    }

    private func addToMeal() {
        let item = AnalysisItem(
            detectedName: product.productName,
            canonicalName: product.productName.lowercased(),
            portionLabel: "\(Int(servingGrams))g serving",
            estimatedGrams: servingGrams,
            uncertainty: "low",
            confidence: 1.0,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            visionConfidence: 0.0,
            dbMatch: true,
            nutritionAvailable: true
        )
        onAddToMeal(EditableAnalysisItem(item: item))
        dismiss()
    }

    private func saveAsCustomFood() {
        LocalMealStore.shared.saveCustomFood(
            name: product.productName,
            servingGrams: servingGrams,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            barcode: product.barcode
        )
        withAnimation { showSavedConfirmation = true }
    }
}

// MARK: - Sub-views

private struct BarcodeNutrientItem: View {
    let value: Int
    let label: String
    var unit: String = ""
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(value)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

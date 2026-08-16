import SwiftUI

// MARK: - Nutrition Summary Banner

struct NutritionSummaryBanner: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    var body: some View {
        HStack(spacing: 0) {
            NutritionBannerItem(value: Int(calories), label: "Cal", color: Theme.calorieValue)
            Divider().frame(height: 40)
            NutritionBannerItem(value: Int(protein), label: "Protein", unit: "g", color: Theme.proteinColor)
            Divider().frame(height: 40)
            NutritionBannerItem(value: Int(carbs), label: "Carbs", unit: "g", color: Theme.carbsColor)
            Divider().frame(height: 40)
            NutritionBannerItem(value: Int(fat), label: "Fat", unit: "g", color: Theme.fatColor)
        }
        .padding(.vertical, 12)
        .background(Theme.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.12)))
        .padding(.horizontal)
    }
}

struct NutritionBannerItem: View {
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

// MARK: - Nutrition Mini Stat

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

// MARK: - Macro Components

struct MacroChip: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text("\(value)g")
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.caption2)
    }
}

struct MacroEditorRow: View {
    @Binding var calories: Double
    @Binding var protein: Double
    @Binding var carbs: Double
    @Binding var fat: Double

    var body: some View {
        HStack(spacing: 8) {
            MacroField(label: "Cal", value: $calories, color: Theme.calorieValue)
            MacroField(label: "P", value: $protein, color: Theme.proteinColor)
            MacroField(label: "C", value: $carbs, color: Theme.carbsColor)
            MacroField(label: "F", value: $fat, color: Theme.fatColor)
        }
    }
}

struct MacroField: View {
    let label: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(4)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.3)))
        }
    }
}

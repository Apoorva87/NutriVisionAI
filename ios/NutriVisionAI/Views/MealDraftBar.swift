import SwiftUI

struct MealDraftBar: View {
    @EnvironmentObject private var draftStore: MealDraftStore
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Item count + calorie total
            VStack(alignment: .leading, spacing: 2) {
                Text("\(draftStore.itemCount) item\(draftStore.itemCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(Int(draftStore.totalCalories)) cal")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            // Macro pills
            HStack(spacing: 8) {
                MacroChip(label: "P", value: Int(draftStore.totalProtein), color: Theme.proteinColor)
                MacroChip(label: "C", value: Int(draftStore.totalCarbs), color: Theme.carbsColor)
                MacroChip(label: "F", value: Int(draftStore.totalFat), color: Theme.fatColor)
            }

            // Review button
            Button(action: onExpand) {
                Text("Review")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.accentGradient)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 12, y: -4)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

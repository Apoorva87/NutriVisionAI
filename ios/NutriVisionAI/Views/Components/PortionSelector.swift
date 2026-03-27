import SwiftUI

struct PortionSelector: View {
    let baseGrams: Double
    @Binding var selectedMultiplier: Double

    private let options: [(label: String, fullName: String, multiplier: Double)] = [
        ("S", "Small", 0.5),
        ("M", "Medium", 1.0),
        ("L", "Large", 1.5),
        ("XL", "Extra Large", 2.0),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.label) { option in
                let isSelected = selectedMultiplier == option.multiplier
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMultiplier = option.multiplier
                    }
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                } label: {
                    VStack(spacing: 2) {
                        Text(option.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("~\(Int(baseGrams * option.multiplier))g")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isSelected ? Theme.accent.opacity(0.12) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Theme.accent.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                }
                .accessibilityLabel("\(option.fullName), approximately \(Int(baseGrams * option.multiplier)) grams")
            }
        }
    }
}

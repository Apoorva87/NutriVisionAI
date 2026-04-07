import SwiftUI

struct PortionSelector: View {
    let baseGrams: Double
    @Binding var selectedMultiplier: Double
    var overrideGrams: Binding<Double?>? = nil

    private let options: [(label: String, fullName: String, multiplier: Double)] = [
        ("S", "Small", 0.5),
        ("M", "Medium", 1.0),
        ("L", "Large", 1.5),
        ("XL", "Extra Large", 2.0),
    ]

    private var displayGrams: Double {
        overrideGrams?.wrappedValue ?? (baseGrams * selectedMultiplier)
    }

    @State private var gramsText: String = ""

    var body: some View {
        VStack(spacing: 8) {
            // Quick preset buttons
            HStack(spacing: 6) {
                ForEach(options, id: \.label) { option in
                    let isSelected = overrideGrams?.wrappedValue == nil && selectedMultiplier == option.multiplier
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMultiplier = option.multiplier
                            overrideGrams?.wrappedValue = nil
                        }
                        gramsText = "\(Int(baseGrams * option.multiplier))"
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 2) {
                            Text(option.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("~\(Int(baseGrams * option.multiplier))g")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(isSelected ? Theme.accent.opacity(0.12) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Theme.accent.opacity(0.3) : Theme.cardBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    }
                    .accessibilityLabel("\(option.fullName), approximately \(Int(baseGrams * option.multiplier)) grams")
                }
            }

            // Slider + editable gram field
            HStack(spacing: 10) {
                Slider(value: $selectedMultiplier, in: 0.25...3.0, step: 0.25)
                    .tint(Theme.accent)
                    .onChange(of: selectedMultiplier) { _, _ in
                        overrideGrams?.wrappedValue = nil
                        gramsText = "\(Int(baseGrams * selectedMultiplier))"
                    }

                TextField("g", text: $gramsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 50)
                    .padding(6)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cardBorder))
                    .onChange(of: gramsText) { _, newValue in
                        if let grams = Double(newValue), grams > 0 {
                            overrideGrams?.wrappedValue = grams
                        }
                    }

                Text("g")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .onAppear {
            gramsText = "\(Int(displayGrams))"
        }
    }
}

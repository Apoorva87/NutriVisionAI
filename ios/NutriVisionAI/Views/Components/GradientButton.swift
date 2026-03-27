import SwiftUI

struct GradientButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    if let icon {
                        Image(systemName: icon)
                    }
                    Text(title)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isDisabled ? AnyShapeStyle(Theme.disabled) : AnyShapeStyle(Theme.accentGradient))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: isDisabled ? .clear : Theme.accentGradientStart.opacity(0.3), radius: 10, y: 4)
        }
        .disabled(isLoading || isDisabled)
        .accessibilityLabel(title)
    }
}

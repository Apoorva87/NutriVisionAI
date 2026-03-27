import SwiftUI

enum Theme {
    // MARK: - Backgrounds
    static let background = Color(red: 15/255, green: 15/255, blue: 15/255)  // #0f0f0f
    static let cardSurface = Color.white.opacity(0.03)
    static let cardBorder = Color.white.opacity(0.06)
    static let cardGlow = Color(red: 167/255, green: 139/255, blue: 250/255).opacity(0.12)

    // MARK: - Accent
    static let accent = Color(red: 167/255, green: 139/255, blue: 250/255)  // #a78bfa
    static let accentGradientStart = Color(red: 124/255, green: 58/255, blue: 237/255)  // #7c3aed
    static let accentGradientEnd = Color(red: 168/255, green: 85/255, blue: 247/255)  // #a855f7
    static let accentGradient = LinearGradient(
        colors: [accentGradientStart, accentGradientEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: - Text
    static let textPrimary = Color(red: 226/255, green: 232/255, blue: 240/255)  // #e2e8f0
    static let textSecondary = Color(red: 148/255, green: 163/255, blue: 184/255)  // #94a3b8
    static let textMuted = Color(red: 71/255, green: 85/255, blue: 105/255)  // #475569

    // MARK: - Macro Gradients
    static let proteinGradient = LinearGradient(
        colors: [Color(red: 56/255, green: 189/255, blue: 248/255), Color(red: 129/255, green: 140/255, blue: 248/255)],
        startPoint: .leading, endPoint: .trailing
    )
    static let carbsGradient = LinearGradient(
        colors: [Color(red: 250/255, green: 204/255, blue: 21/255), Color(red: 251/255, green: 146/255, blue: 60/255)],
        startPoint: .leading, endPoint: .trailing
    )
    static let fatGradient = LinearGradient(
        colors: [Color(red: 251/255, green: 113/255, blue: 133/255), Color(red: 232/255, green: 121/255, blue: 249/255)],
        startPoint: .leading, endPoint: .trailing
    )

    // MARK: - Solid Macro Colors (for text labels)
    static let proteinColor = Color(red: 129/255, green: 140/255, blue: 248/255)  // #818cf8
    static let carbsColor = Color(red: 251/255, green: 191/255, blue: 36/255)  // #fbbf24
    static let fatColor = Color(red: 251/255, green: 113/255, blue: 133/255)  // #fb7185

    // MARK: - Semantic
    static let positive = Color(red: 34/255, green: 211/255, blue: 238/255)  // #22d3ee
    static let destructive = Color(red: 239/255, green: 68/255, blue: 68/255)  // #ef4444
    static let successStart = Color(red: 34/255, green: 197/255, blue: 94/255)  // #22c55e
    static let successEnd = Color(red: 22/255, green: 163/255, blue: 74/255)  // #16a34a
    static let successGradient = LinearGradient(
        colors: [successStart, successEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let calorieValue = Color(red: 192/255, green: 132/255, blue: 252/255)  // #c084fc
    static let disabled = Color(red: 71/255, green: 85/255, blue: 105/255)  // #475569 (matches textMuted)

    // MARK: - Card Style Modifier
    static func cardStyle(glow: Bool = false) -> some ViewModifier {
        CardStyleModifier(glow: glow)
    }

    // MARK: - Thumbnail gradient backgrounds
    static let thumbnailGradients: [LinearGradient] = [
        LinearGradient(colors: [Color(red: 76/255, green: 29/255, blue: 149/255), Color(red: 109/255, green: 40/255, blue: 217/255)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 30/255, green: 58/255, blue: 95/255), Color(red: 37/255, green: 99/255, blue: 235/255)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 127/255, green: 29/255, blue: 29/255), Color(red: 220/255, green: 38/255, blue: 38/255)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 6/255, green: 95/255, blue: 70/255), Color(red: 4/255, green: 120/255, blue: 87/255)], startPoint: .topLeading, endPoint: .bottomTrailing),
    ]
}

struct CardStyleModifier: ViewModifier {
    let glow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .background(Theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(glow ? Theme.cardGlow : Theme.cardBorder, lineWidth: 1)
            )
            .shadow(color: (glow && !reduceMotion) ? Theme.accent.opacity(0.06) : .clear, radius: 12)
    }
}

extension View {
    func themedCard(glow: Bool = false) -> some View {
        modifier(CardStyleModifier(glow: glow))
    }
}

// MARK: - Accessibility: Reduce Motion helper

/// Generic modifier that swaps spring animations for `.default` when reduceMotion is on.
struct ReduceMotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Use instead of `.animation(...)` on spring/glow animations to respect reduceMotion.
    func motionSafeAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReduceMotionModifier(animation: animation, value: value))
    }
}

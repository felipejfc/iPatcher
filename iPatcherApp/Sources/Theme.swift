import SwiftUI

// MARK: - iPatcher Design System

enum IPTheme {
    // Core palette
    static let accent       = Color(red: 0.0, green: 0.82, blue: 1.0)   // Electric cyan
    static let accentAlt    = Color(red: 0.4, green: 0.3,  blue: 1.0)   // Deep purple
    static let background   = Color(red: 0.06, green: 0.06, blue: 0.09)
    static let surface      = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let surfaceLight = Color(red: 0.16, green: 0.16, blue: 0.20)

    // Text
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.55)

    // Semantic
    static let success = Color(red: 0.2, green: 0.9, blue: 0.4)
    static let warning = Color(red: 1.0, green: 0.7, blue: 0.0)
    static let danger  = Color(red: 1.0, green: 0.3, blue: 0.3)

    // Gradients
    static let accentGradient = LinearGradient(
        colors: [accent, accentAlt],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Typography
    static let monoSmall  = Font.system(size: 12, design: .monospaced)
    static let monoMedium = Font.system(size: 14, design: .monospaced)
    static let monoLarge  = Font.system(size: 16, design: .monospaced)
}

// MARK: - Card modifier

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(IPTheme.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

// MARK: - Glow Button

struct GlowButtonStyle: ButtonStyle {
    var color: Color = IPTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(configuration.isPressed ? 0.5 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: color.opacity(configuration.isPressed ? 0.1 : 0.35),
                    radius: configuration.isPressed ? 4 : 12)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(IPTheme.textSecondary)
                .tracking(1.2)
            Spacer()
            if let trailing { trailing }
        }
    }
}

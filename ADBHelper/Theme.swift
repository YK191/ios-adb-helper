import SwiftUI

// Shared visual language for all screens: deep navy + mint/blue accents,
// soft cards, clear status and generous spacing.
enum AppTheme {
    static let mint = Color(0x34D8BE)
    static let blue = Color(0x3AA7F2)
    static let ink = Color(0x0B1B2B)
    static let text = Color.primary
    static let secondary = Color.secondary
    static let card = Color(uiColor: .secondarySystemBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let border = Color.white.opacity(0.07)
    static let success = Color(0x2FBF71)
    static let danger = Color(0xE5534B)

    static let accentGradient = LinearGradient(
        colors: [mint, blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let warmGradient = LinearGradient(
        colors: [Color(0xFFB86B), Color(0xFF7A59)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let canvasGradient = LinearGradient(
        colors: [mint.opacity(0.13), blue.opacity(0.10), Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Color {
    init(_ hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct AppCard: ViewModifier {
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    func appCard(padding: CGFloat = 14, radius: CGFloat = 16) -> some View {
        modifier(AppCard(padding: padding, cornerRadius: radius))
    }

    func appCanvas() -> some View {
        background(Rectangle().fill(AppTheme.canvasGradient).ignoresSafeArea())
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    var tint: Color = AppTheme.mint

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle = subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct StatusPill: View {
    let connected: Bool
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? AppTheme.success : Color.secondary.opacity(0.55))
                .frame(width: 7, height: 7)
                .shadow(color: connected ? AppTheme.success.opacity(0.6) : .clear, radius: 4)
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            (connected ? AppTheme.success : Color.secondary).opacity(0.12),
            in: Capsule()
        )
        .foregroundStyle(connected ? AppTheme.success : .secondary)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.mint.opacity(0.7))
            Text(title).font(.subheadline.weight(.semibold))
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 18)
            .background(AppTheme.accentGradient, in: Capsule())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.mint)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(AppTheme.mint.opacity(configuration.isPressed ? 0.22 : 0.12), in: Capsule())
    }
}

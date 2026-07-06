import SwiftUI

// MARK: - Premium Press Style

/// A reusable button style that provides premium press feedback
/// Scales to 0.985 and reduces opacity to 0.96 on press
/// Respects Reduce Motion accessibility setting
struct PremiumPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.96 : 1.0)
            .animation(AppMotion.Spring.press, value: configuration.isPressed)
            .contentShape(Rectangle()) // Makes entire area tappable
    }
}

// MARK: - Hero Card Wrapper

/// A wrapper view that provides hero transition support for navigation
/// Use this to wrap cards/columns that should morph into destination screens
struct HeroCard<Content: View>: View {
    let id: String
    let namespace: Namespace.ID?
    @ViewBuilder let content: () -> Content
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Group {
            if let namespace = namespace, !reduceMotion {
                content()
                    .matchedGeometryEffect(id: id, in: namespace)
            } else {
                content()
            }
        }
    }
}

// MARK: - Hero Destination Wrapper

/// A wrapper for destination screens to receive the hero transition
/// Mirrors the source card's geometry effect
struct HeroDestination<Content: View>: View {
    let id: String
    let namespace: Namespace.ID?
    @ViewBuilder let content: () -> Content
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Group {
            if let namespace = namespace, !reduceMotion {
                content()
                    .matchedGeometryEffect(id: id, in: namespace)
            } else {
                content()
            }
        }
    }
}

// MARK: - Premium Navigation Link

/// A NavigationLink wrapper that combines premium press feedback with hero transitions
struct PremiumNavigationLink<Label: View, Destination: View>: View {
    let heroID: String
    let namespace: Namespace.ID?
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Label
    
    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HeroCard(id: heroID, namespace: namespace) {
                label()
            }
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Tap Burst Button Style

/// More pronounced press feedback for primary action buttons.
/// Scales down to 0.92 on press and bounces back with a snappy overshoot on release.
/// Respects Reduce Motion.
struct TapBurstButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1.0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(
                configuration.isPressed
                    ? AppMotion.Spring.press
                    : AppMotion.Spring.celebratory,
                value: configuration.isPressed
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Tap Burst Effect

/// Radiating ring + brief shine flash that fires each time `trigger` changes.
/// Drop on any button-shaped view to add a celebratory pulse when the action runs.
struct TapBurstModifier: ViewModifier {
    let trigger: Int
    var cornerRadius: CGFloat = AppDesignSystem.Radius.md
    var color: Color = AppTheme.Colors.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.0
    @State private var flashOpacity: Double = 0.0
    @State private var popScale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(popScale)
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(flashOpacity))
                        .blendMode(.plusLighter)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(color.opacity(ringOpacity), lineWidth: 3)
                        .scaleEffect(ringScale)
                        .blur(radius: 0.5)
                }
                .allowsHitTesting(false)
            )
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                runBurst()
            }
    }

    private func runBurst() {
        ringScale = 1.0
        ringOpacity = 0.85
        flashOpacity = 0.35
        popScale = 1.0

        withAnimation(AppMotion.Spring.celebratory) {
            popScale = 1.06
        }
        withAnimation(AppMotion.Spring.smooth.delay(0.12)) {
            popScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.55)) {
            ringScale = 1.22
            ringOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.35)) {
            flashOpacity = 0
        }
    }
}

// MARK: - Helper Extension

extension View {
    /// Applies premium press feedback to any view
    func premiumPress() -> some View {
        buttonStyle(PremiumPressStyle())
    }

    /// Plays an expanding ring + brief shine + scale pop each time `trigger` changes.
    /// Use alongside a button action that increments the trigger.
    func tapBurst(
        trigger: Int,
        cornerRadius: CGFloat = AppDesignSystem.Radius.md,
        color: Color = AppTheme.Colors.accent
    ) -> some View {
        modifier(TapBurstModifier(trigger: trigger, cornerRadius: cornerRadius, color: color))
    }
    
    /// Wraps a view with hero transition support
    func heroCard(id: String, in namespace: Namespace.ID?) -> some View {
        HeroCard(id: id, namespace: namespace) {
            self
        }
    }
    
    /// Wraps a destination view with hero transition support
    func heroDestination(id: String, in namespace: Namespace.ID?) -> some View {
        HeroDestination(id: id, namespace: namespace) {
            self
        }
    }
}

// MARK: - Hero-Enabled Section Card

/// A SectionCard variant that supports hero transitions
/// Use this for dashboard sections that navigate to detail screens
struct HeroSectionCard<Content: View>: View {
    let heroID: String
    let namespace: Namespace.ID?
    let title: String?
    let subtitle: String?
    let trailing: AnyView?
    var centerHeader: Bool = false
    @ViewBuilder let content: () -> Content
    
    init(
        heroID: String,
        namespace: Namespace.ID?,
        title: String?,
        subtitle: String?,
        trailing: AnyView? = nil,
        centerHeader: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.heroID = heroID
        self.namespace = namespace
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.centerHeader = centerHeader
        self.content = content
    }
    
    var body: some View {
        HeroCard(id: heroID, namespace: namespace) {
            SectionCard(
                title: title,
                subtitle: subtitle,
                trailing: trailing,
                centerHeader: centerHeader,
                content: content
            )
        }
    }
}

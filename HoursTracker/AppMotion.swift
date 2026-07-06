import SwiftUI

// MARK: - Motion tokens & helpers

enum AppMotion {
    enum Spring {
        static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.86)
        static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.88)
        static let celebratory = Animation.spring(response: 0.48, dampingFraction: 0.74)
        static let press = Animation.spring(response: 0.26, dampingFraction: 0.78)
        static let podium = Animation.spring(response: 0.55, dampingFraction: 0.82)
    }

    enum Duration {
        static let fast: Double = 0.2
        static let standard: Double = 0.32
        static let slow: Double = 0.5
    }

    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: Duration.fast) : base
    }

    static func staggerDelay(index: Int, step: Double = 0.055, cap: Double = 0.45) -> Double {
        min(cap, Double(index) * step)
    }
}

// MARK: - Card entrance

@MainActor
private enum CardAppearState {
    static var completedIndices = Set<Int>()
}

private struct CardAppearModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : (reduceMotion ? 0 : 8))
            .onAppear {
                if CardAppearState.completedIndices.contains(index) {
                    visible = true
                    return
                }
                CardAppearState.completedIndices.insert(index)
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(AppMotion.Spring.smooth.delay(AppMotion.staggerDelay(index: index))) {
                        visible = true
                    }
                }
            }
    }
}

// MARK: - Podium rise

struct PodiumRiseModifier: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(y: risen ? 1 : (reduceMotion ? 1 : 0.72), anchor: .bottom)
            .opacity(risen ? 1 : 0)
            .offset(y: risen ? 0 : (reduceMotion ? 0 : 18))
            .onAppear {
                if reduceMotion {
                    risen = true
                } else {
                    withAnimation(AppMotion.Spring.podium.delay(delay)) {
                        risen = true
                    }
                }
            }
    }
}

// MARK: - Save checkmark flash

struct SaveCheckmarkOverlay: View {
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0

    var body: some View {
        if isVisible {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.success.opacity(0.18))
                    .frame(width: 92, height: 92)
                    .blur(radius: 2)
                Circle()
                    .stroke(AppTheme.Colors.success.opacity(0.45), lineWidth: 2)
                    .frame(width: 92, height: 92)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.success)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onAppear {
                if reduceMotion {
                    scale = 1
                    opacity = 1
                } else {
                    withAnimation(AppMotion.Spring.celebratory) {
                        scale = 1
                        opacity = 1
                    }
                }
            }
        }
    }
}

// MARK: - Badge glow unlock (inline / sheet hero)

struct BadgeGlowHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowScale: CGFloat = 0.85
    @State private var glowOpacity: Double = 0
    @State private var iconScale: CGFloat = 0.7

    var systemImage: String = "medal.fill"

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.Colors.accent.opacity(0.35), Color.clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 56
                    )
                )
                .frame(width: 112, height: 112)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)

            Circle()
                .fill(AppTheme.Colors.accent.opacity(0.16))
                .frame(width: 86, height: 86)

            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.accent)
                .scaleEffect(iconScale)
        }
        .onAppear {
            if reduceMotion {
                glowScale = 1
                glowOpacity = 1
                iconScale = 1
            } else {
                withAnimation(AppMotion.Spring.celebratory) {
                    iconScale = 1
                    glowOpacity = 1
                    glowScale = 1.08
                }
                withAnimation(AppMotion.Spring.smooth.delay(0.2)) {
                    glowScale = 1
                }
            }
        }
    }
}

// MARK: - Soft loading indicator

struct SoftLoadingIndicator: View {
    var title: String = "Loading…"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(0.95)
                .tint(AppTheme.Colors.accent)
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)
                .opacity(pulse ? 1 : 0.65)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Animated metric text

struct AnimatedMetricText: View {
    let value: Double
    var format: (Double) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Double, format: @escaping (Double) -> String) {
        self.value = value
        self.format = format
    }

    init(hours value: Double) {
        self.value = value
        self.format = { AppTheme.Format.hours($0) }
    }

    init(currency value: Double, code: String) {
        self.value = value
        self.format = { amount in
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = code
            return f.string(from: NSNumber(value: amount)) ?? "—"
        }
    }

    var body: some View {
        Text(format(value))
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: value)
    }
}

struct AnimatedIntText: View {
    let value: Int
    var suffix: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(value)\(suffix)")
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: value)
    }
}

// MARK: - Reaction pop button style

struct ReactionPopButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 1.14 : 1)
            .animation(AppMotion.Spring.press, value: configuration.isPressed)
    }
}

// MARK: - Segmented chip (category pickers)

struct MotionSegmentChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.semanticColors) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Haptics.lightTap()
            withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
                action()
            }
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(theme.accentGradientColors.first ?? theme.accent)
                        Capsule()
                            .stroke(theme.accentHighlight.opacity(0.55), lineWidth: 1)
                    } else {
                        Capsule()
                            .fill(theme.cardSecondary)
                        Capsule()
                            .stroke(theme.border, lineWidth: 0.5)
                    }
                }
            )
            .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1)
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - List row stagger (avoid on LazyVStack / live-updating lists)

private struct ListRowAppearModifier: ViewModifier {
    let rowID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : (reduceMotion ? 0 : 8))
            .onAppear {
                if ListRowAppearState.completedIDs.contains(rowID) {
                    visible = true
                    return
                }
                ListRowAppearState.completedIDs.insert(rowID)
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(AppMotion.Spring.smooth.delay(0.04)) {
                        visible = true
                    }
                }
            }
    }
}

@MainActor
private enum ListRowAppearState {
    static var completedIDs = Set<String>()
}

// MARK: - Gentle fade state (empty / loading)

struct GentleFadeIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : (reduceMotion ? 0 : 6))
            .onAppear {
                guard !visible else { return }
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(AppMotion.Spring.smooth) {
                        visible = true
                    }
                }
            }
    }
}

// MARK: - View extensions

extension View {
    func cardAppear(index: Int) -> some View {
        modifier(CardAppearModifier(index: index))
    }

    func podiumRise(delay: Double = 0) -> some View {
        modifier(PodiumRiseModifier(delay: delay))
    }

    func listRowAppear(id: String) -> some View {
        modifier(ListRowAppearModifier(rowID: id))
    }

    func gentleFadeIn() -> some View {
        modifier(GentleFadeIn())
    }

    /// Keeps stat labels from sliding/scaling when sibling views animate (e.g. XP bar fill).
    func stableCardLabel() -> some View {
        self
            .contentTransition(.identity)
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}

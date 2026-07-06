import SwiftUI

// MARK: - Auto-Dismiss Date Picker Sheet (dismisses after user selects a date)
struct AutoDismissDatePickerSheet: View {
    @Binding var date: Date
    let title: String
    let onDismiss: () -> Void

    @State private var selectedDate: Date
    @State private var hasAppeared = false

    init(date: Binding<Date>, title: String = "Select Date", onDismiss: @escaping () -> Void) {
        self._date = date
        self.title = title
        self.onDismiss = onDismiss
        self._selectedDate = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .onChange(of: selectedDate) { _, newValue in
                    guard hasAppeared else { return }
                    date = newValue
                    onDismiss()
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        hasAppeared = true
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            date = selectedDate
                            onDismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Spacing helpers
extension CGFloat {
    static var top: CGFloat { 12 }
    static var horizontal: CGFloat { 16 }
}

// MARK: - AppCard (vibrant gradient border + subtle glow)
struct AppCard<Content: View>: View {
    /// When true, intensifies the accent stroke + glow (used for hero cards).
    var accentTint: Bool = false
    @ViewBuilder let content: () -> Content

    init(accentTint: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.accentTint = accentTint
        self.content = content
    }

    var body: some View {
        let strokeOpacity: Double = accentTint ? 0.45 : 0.25
        let glowOpacity: Double = accentTint ? 0.18 : 0.08

        content()
            .padding(AppDesignSystem.Spacing.md)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                        .fill(AppTheme.Colors.card)
                    RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                        .fill(AppTheme.Colors.cardGradient)
                    RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.Colors.accent.opacity(0.06), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.accent.opacity(strokeOpacity),
                                AppTheme.Colors.stroke,
                                AppTheme.Colors.accentHighlight.opacity(strokeOpacity * 0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: AppTheme.Colors.accent.opacity(glowOpacity), radius: 14, x: 0, y: 6)
    }
}

// MARK: - SectionHeader (game-style uppercase rounded)
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(AppDesignSystem.Typography.sectionLabel)
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.text.opacity(0.85))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
        }
    }
}

// MARK: - Interactive Button Style (scale + bounce on press)
struct InteractiveButtonStyle: ButtonStyle {
    var minScale: CGFloat = 0.95
    var pressedOpacity: Double = 0.85
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? minScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(AppMotion.Spring.press, value: configuration.isPressed)
    }
}

// MARK: - PrimaryButton (vibrant gradient + glow + bounce)
struct PrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let isSuccess: Bool
    private let action: () -> Void

    @State private var glowOpacity: Double = 0.15
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, systemImage: String? = nil, isSuccess: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSuccess = isSuccess
        self.action = action
    }

    init(title: String, systemImage: String? = nil, isSuccess: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSuccess = isSuccess
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .fill(buttonFill)
            )
            .shadow(color: buttonShadowColor.opacity(0.4), radius: 12, x: 0, y: 5)
            .overlay {
                if !isSuccess {
                    RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                        .stroke(AppTheme.Colors.accent.opacity(glowOpacity), lineWidth: 3)
                        .blur(radius: 6)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(InteractiveButtonStyle(minScale: 0.94))
        .disabled(isSuccess)
        .animation(.easeInOut(duration: 0.25), value: isSuccess)
        .onAppear {
            guard !isSuccess, !reduceMotion else {
                glowOpacity = 0.45
                return
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowOpacity = 0.65
            }
        }
    }

    private var buttonFill: AnyShapeStyle {
        if isSuccess {
            return AnyShapeStyle(AppTheme.Colors.success)
        }
        return AnyShapeStyle(AppTheme.Colors.accentGradient)
    }

    private var buttonShadowColor: Color {
        isSuccess ? AppTheme.Colors.success : AppTheme.Colors.accent
    }
}

// MARK: - SectionCard (card container with optional header)
struct SectionCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let trailing: AnyView?
    var centerHeader: Bool = false
    @ViewBuilder let content: () -> Content

    init(
        title: String?,
        subtitle: String?,
        trailing: AnyView?,
        centerHeader: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.centerHeader = centerHeader
        self.content = content
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                if title != nil || subtitle != nil || trailing != nil {
                    HStack(alignment: .top, spacing: 12) {
                        if centerHeader && trailing == nil {
                            VStack(spacing: 4) {
                                if let title {
                                    Text(title)
                                        .font(AppDesignSystem.Typography.title3)
                                        .foregroundStyle(AppTheme.Colors.text)
                                        .multilineTextAlignment(.center)
                                }
                                if let subtitle {
                                    Text(subtitle)
                                        .font(AppDesignSystem.Typography.callout)
                                        .foregroundStyle(AppTheme.Colors.subtext)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                if let title {
                                    Text(title)
                                        .font(AppDesignSystem.Typography.title3)
                                        .foregroundStyle(AppTheme.Colors.text)
                                }
                                if let subtitle {
                                    Text(subtitle)
                                        .font(AppDesignSystem.Typography.callout)
                                        .foregroundStyle(AppTheme.Colors.subtext)
                                }
                            }
                            Spacer()
                            if let trailing { trailing }
                        }
                    }
                }
                content()
                    .frame(maxWidth: centerHeader ? .infinity : nil, alignment: centerHeader ? .center : .leading)
            }
        }
    }
}

// MARK: - StatTile (metric tile with accent glow)
struct StatTile: View {
    var label: String
    var value: String
    var accent: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(value)
                .font(AppDesignSystem.Typography.heroNumerals(size: 24, weight: .bold))
                .foregroundStyle(accent ?? AppTheme.Colors.text)
                .shadow(color: (accent ?? AppTheme.Colors.accent).opacity(0.3), radius: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.card2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            (accent ?? AppTheme.Colors.accent).opacity(0.25),
                            AppTheme.Colors.stroke,
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - EmptyStateView (motivating game-style)
struct EmptyStateView: View {
    var icon: String = "tray"
    var title: String
    var subtitle: String? = nil
    var primaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    @State private var iconPulse: CGFloat = 1.0
    @State private var contentVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(icon: String, title: String, message: String, actionTitle: String, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = message
        self.primaryTitle = actionTitle
        self.primaryAction = action
    }

    init(icon: String = "tray", title: String, subtitle: String? = nil,
         primaryTitle: String? = nil, primaryAction: (() -> Void)? = nil,
         secondaryTitle: String? = nil, secondaryAction: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.15))
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .scaleEffect(iconPulse)
            }
            .padding(.top, 4)

            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            }

            if let primaryTitle, let primaryAction {
                PrimaryButton(primaryTitle, systemImage: "plus") { primaryAction() }
                    .padding(.top, 4)
            }
            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                                .fill(AppTheme.Colors.accentGradient)
                                .shadow(color: AppTheme.Colors.accent.opacity(0.4), radius: 8, y: 3)
                        )
                }
                .buttonStyle(InteractiveButtonStyle())
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : (reduceMotion ? 0 : 8))
        .onAppear {
            if reduceMotion {
                contentVisible = true
            } else {
                withAnimation(AppMotion.Spring.smooth) {
                    contentVisible = true
                }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    iconPulse = 1.06
                }
            }
        }
    }
}

import SwiftUI

// MARK: - Settings row components (Phase 10)
//
// Mirrors the AccountNavRow recipe (icon in a small tinted rounded square,
// headline title, caption subtitle) for use inside native Form rows, where
// the Form supplies insets, separators, and row backgrounds.

/// Small tinted rounded icon square — the leading treatment for every
/// Settings row. Same recipe as `AccountNavRow`'s square.
struct SettingsIconSquare: View {
    let icon: String
    var tint: Color = AppColors.accent
    var isBusy: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
            .fill(tint.opacity(0.14))
            .frame(width: 30, height: 30)
            .overlay {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(tint)
                } else {
                    Image(systemName: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
    }
}

/// Icon square + title (+ optional subtitle) — label for toggles, nav links
/// and buttons inside a Form row.
struct SettingsRowLabel: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = AppColors.accent
    var titleTint: Color = AppColors.text
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            SettingsIconSquare(icon: icon, tint: tint, isBusy: isBusy)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appText(.headline)
                    .foregroundStyle(titleTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .lineLimit(2)
                }
            }
        }
    }
}

/// Trailing chevron for button rows that open sheets (NavigationLink rows get
/// the system chevron for free).
struct SettingsChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColors.faint)
    }
}

/// Full value row: icon square, title, current value in subtext, chevron.
struct SettingsValueRow: View {
    let icon: String
    let title: String
    let value: String
    var tint: Color = AppColors.accent

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            SettingsIconSquare(icon: icon, tint: tint)
            Text(title)
                .appText(.headline)
                .foregroundStyle(AppColors.text)
            Spacer(minLength: AppSpacing.xs)
            Text(value)
                .appText(.caption)
                .monospacedDigit()
                .foregroundStyle(AppColors.subtext)
            SettingsChevron()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Friends Privacy (Settings)

struct FriendsPrivacySettingsView: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var socialPrivacy = SocialPrivacyStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: shareHoursBinding) {
                    SettingsRowLabel(
                        icon: "clock.fill",
                        title: "Show hours to friends",
                        subtitle: "Weekly + total hours on the leaderboard"
                    )
                }
                .tint(AppColors.accent)
                NavigationLink {
                    CountryFlagPickerView(store: store)
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        SettingsRowLabel(
                            icon: "flag.fill",
                            title: "Country flag",
                            subtitle: "Shown beside your name on Top 5 Hour Trackers"
                        )
                        Spacer(minLength: AppSpacing.xs)
                        if let flag = CountryFlag.emoji(for: CountryFlag.resolvedCode) {
                            Text(flag)
                                .font(.title3)
                        }
                    }
                }
                Toggle(isOn: shareBadgesBinding) {
                    SettingsRowLabel(
                        icon: "rosette",
                        title: "Show badges to friends",
                        subtitle: "Badge count + equipped title"
                    )
                }
                .tint(AppColors.accent)
                Toggle(isOn: shareActivityBinding) {
                    SettingsRowLabel(
                        icon: "sparkles",
                        title: "Post to activity feed",
                        subtitle: "Shifts, badges, milestones + friend alerts"
                    )
                }
                .tint(AppColors.accent)
                Toggle(isOn: acceptInvitesBinding) {
                    SettingsRowLabel(
                        icon: "person.crop.circle.badge.plus",
                        title: "Accept friend invites",
                        subtitle: "Allow others to send you requests"
                    )
                }
                .tint(AppColors.accent)
            } header: {
                SectionEyebrow("Sharing")
            } footer: {
                Text("Friends only see what you share. Your country flag appears on the public Top 5 board when hours sharing is on.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
            .listRowBackground(AppColors.card.opacity(0.55))
            .listRowSeparatorTint(AppColors.stroke)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("Friends privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var shareHoursBinding: Binding<Bool> {
        Binding(
            get: { socialPrivacy.flags.shareHours },
            set: { newValue in
                Haptics.lightTap()
                socialPrivacy.update { $0.shareHours = newValue }
                store.syncProfileSnapshotToCloud()
            }
        )
    }

    private var shareBadgesBinding: Binding<Bool> {
        Binding(
            get: { socialPrivacy.flags.shareBadges },
            set: { newValue in
                Haptics.lightTap()
                socialPrivacy.update { $0.shareBadges = newValue }
                store.syncProfileSnapshotToCloud()
            }
        )
    }

    private var shareActivityBinding: Binding<Bool> {
        Binding(
            get: { socialPrivacy.flags.shareActivity },
            set: { newValue in
                Haptics.lightTap()
                socialPrivacy.update { $0.shareActivity = newValue }
                store.syncProfileSnapshotToCloud()
            }
        )
    }

    private var acceptInvitesBinding: Binding<Bool> {
        Binding(
            get: { socialPrivacy.flags.acceptInvites },
            set: { newValue in
                Haptics.lightTap()
                socialPrivacy.update { $0.acceptInvites = newValue }
                store.syncProfileSnapshotToCloud()
            }
        )
    }
}

// MARK: - OT Hours Stepper

/// Compact stepper widget showing the current value with +/− buttons.
struct OTHoursStepper: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    /// Nil = hours label ("8h" / "8.5h"). Pass "×%.2g" for multiplier display.
    var format: String? = nil

    private var formattedValue: String {
        if let fmt = format {
            return String(format: fmt, value)
        }
        let rounded = (value * 10).rounded() / 10
        let isWhole = rounded == rounded.rounded(.towardZero)
        return isWhole ? "\(Int(rounded))h" : "\(rounded)h"
    }

    var body: some View {
        HStack(spacing: 6) {
            stepButton(
                systemName: "minus",
                enabled: value > range.lowerBound + 0.0001
            ) {
                adjust(by: -step)
            }

            Text(formattedValue)
                .appText(.headline)
                .foregroundStyle(AppColors.text)
                .monospacedDigit()
                .frame(minWidth: 52)
                .multilineTextAlignment(.center)
                .allowsHitTesting(false)

            stepButton(
                systemName: "plus",
                enabled: value < range.upperBound - 0.0001
            ) {
                adjust(by: step)
            }
        }
        .padding(AppSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.card2)
        )
    }

    private func stepButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .foregroundStyle(enabled ? AppColors.accent : AppColors.faint)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                        .fill(enabled ? AppColors.accent.opacity(0.12) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func adjust(by delta: Double) {
        Haptics.lightTap()
        var next = value + delta
        next = min(range.upperBound, max(range.lowerBound, next))
        if step > 0 {
            next = (next / step).rounded() * step
            next = min(range.upperBound, max(range.lowerBound, next))
        }
        value = next
    }
}

import SwiftUI

// MARK: - Friends tab sections (Phase 6)
//
// Quiet-card building blocks for the Friends hub: the friend-code card,
// request / friend rows, the segment model, and the leaderboard link cards.
// All colors come from tokens; hairline strokes, flat fills, no glows.

// MARK: - Segments

/// The three panes of the Friends hub. Raw value doubles as the persisted
/// `@AppStorage` key value so the selection survives relaunches.
enum FriendsSegment: String, CaseIterable, Identifiable {
    case friends = "Friends"
    case activity = "Activity"
    case boards = "Leaderboards"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .friends: return "person.2"
        case .activity: return "bolt"
        case .boards: return "trophy"
        }
    }
}

// MARK: - Friend code card

/// Quiet card combining the user's shareable code (tap to copy) with the
/// add-by-code field. Behavior matches the old hero card; the dress is now
/// flat card fill + hairline stroke instead of gradient + glow.
struct FriendCodeCard: View {
    let code: String?
    @Binding var codeInput: String
    let isSending: Bool
    let copyConfirmation: Bool
    let onCopy: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            VStack(spacing: AppSpacing.xs) {
                Text("Your Friend Code")
                    .appText(.eyebrow)
                    .foregroundStyle(AppColors.subtext)

                Button(action: onCopy) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(code ?? "—")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColors.text)
                            .monospacedDigit()
                        Image(systemName: copyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(copyConfirmation ? AppColors.positive : AppColors.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(code == nil)

                Text(copyConfirmation ? "Copied to clipboard" : "Tap to copy your code")
                    .appText(.caption)
                    .foregroundStyle(copyConfirmation ? AppColors.positive : AppColors.faint)
            }

            Rectangle()
                .fill(AppColors.stroke)
                .frame(height: 1)

            addFriendRow
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(AppColors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }

    private var addFriendRow: some View {
        HStack(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.subtext)
                TextField("Enter friend code", text: $codeInput)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(AppColors.text)
                    .onChange(of: codeInput) { _, newValue in
                        let sanitized = newValue
                            .uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                        if sanitized != newValue || sanitized.count > 8 {
                            codeInput = String(sanitized.prefix(8))
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColors.card)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 1)
                    )
            )

            Button(action: onAdd) {
                Group {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppColors.textOnAccent)
                    } else {
                        Text("Add")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textOnAccent)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(Capsule(style: .continuous).fill(AppColors.accent))
            }
            .buttonStyle(PremiumPressStyle())
            .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            .opacity(codeInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)
        }
    }
}

// MARK: - Friend row

/// One friend in the Friends segment: avatar + level capsule, name and level
/// line, then weekly hours with a relative capsule bar and the streak flame.
struct FriendStatsRow: View {
    let friend: FriendProfile
    /// Highest shared `weeklyHours` among visible friends — drives the
    /// relative fill of the capsule bar. Pass 0 when nobody shares hours.
    var maxWeeklyHours: Double = 0
    var onOpenProfile: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatarView(
                    name: friend.displayName,
                    size: 48,
                    photoURL: friend.profilePhotoURL,
                    uid: friend.uid
                )
                Text("\(friend.level)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textOnAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.accent))
                    .overlay(Capsule().stroke(AppColors.card, lineWidth: 2))
                    .offset(x: 5, y: 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                Text(friend.levelDisplayLine)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.xs)

            if friend.privacy.shareHours {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(AppTheme.Format.hours(friend.weeklyHours))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.text)
                            .monospacedDigit()
                        streakChip
                    }
                    relativeHoursBar
                    Text("this week")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.faint)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Hours hidden")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AppColors.subtext)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppColors.card))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.faint)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.lightTap()
            onOpenProfile?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens friend profile")
    }

    private var streakChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppColors.streak)
            Text("\(friend.currentStreak)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.subtext)
                .monospacedDigit()
        }
    }

    /// Thin capsule showing this friend's week relative to the group max.
    private var relativeHoursBar: some View {
        let fraction: Double = maxWeeklyHours > 0
            ? min(1, max(0, friend.weeklyHours / maxWeeklyHours))
            : 0
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(AppColors.stroke.opacity(0.65))
            Capsule()
                .fill(AppColors.accent)
                .frame(width: max(4, 64 * fraction))
        }
        .frame(width: 64, height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Request row

struct FriendRequestRow: View {
    let request: FriendRequestItem
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                name: request.fromName,
                size: 44,
                photoURL: nil,
                uid: request.fromUid
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(request.fromName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                Text("Wants to be friends")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }

            Spacer()

            Button(action: onDecline) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.subtext)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(AppColors.card)
                            .overlay(Circle().stroke(AppColors.stroke, lineWidth: 1))
                    )
            }
            .buttonStyle(PremiumPressStyle())
            .accessibilityLabel("Decline request from \(request.fromName)")

            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.textOnAccent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AppColors.accent))
            }
            .buttonStyle(PremiumPressStyle())
            .accessibilityLabel("Accept request from \(request.fromName)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Leaderboard link cards

/// Tappable card in the Leaderboards segment — pushes an existing
/// leaderboard screen (interiors are Phase 7; only the entry point lives here).
struct LeaderboardLinkCard<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                    Text(subtitle)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                Spacer(minLength: AppSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.faint)
            }
            .padding(AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressStyle())
    }
}

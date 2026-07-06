import SwiftUI

/// Reverse-chronological list of recent activity from the user and their
/// friends. Reads from `ActivityFeedService.events` which is kept fresh by
/// per-author snapshot listeners; the view itself is a thin presentation layer.
struct ActivityFeedView: View {

    @ObservedObject var feed: ActivityFeedService
    @ObservedObject var friendsService: FriendsService
    @EnvironmentObject private var authService: AuthService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.semanticColors) private var theme

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            content
                .background(AppTheme.Colors.bg.ignoresSafeArea())
                .navigationTitle("Activity")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .buttonStyle(PremiumPressStyle())
                    }
                }
                .onAppear {
                    refreshSubscription()
                    Task { await friendsService.refreshFriendProfiles() }
                }
                .onChange(of: authService.user?.uid) { _, _ in
                    refreshSubscription()
                }
                .onChange(of: friendsService.friends.map { "\($0.uid):\($0.weeklyHours):\($0.totalHours)" }) { _, _ in
                    refreshSubscription()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = feed.errorMessage, feed.events.isEmpty {
            errorState(error)
        } else if feed.isLoading && feed.events.isEmpty {
            SoftLoadingIndicator(title: "Catching up on friends…")
        } else if feed.events.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(feed.events) { event in
                        eventRow(event)
                    }
                }
                .animation(nil, value: feed.events.map(\.id))
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppTheme.Colors.danger)
            Text("Couldn't load activity")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Try again") {
                Haptics.lightTap()
                refreshSubscription()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(AppTheme.Colors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gentleFadeIn()
    }

    private func eventRow(_ event: ActivityEvent) -> some View {
        Button {
            Haptics.lightTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: event.iconName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    (Text(event.authorDisplayName)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    + Text(" ")
                    + Text(event.body)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundColor(theme.textPrimary))
                        .lineLimit(2)

                    Text(relativeFormatter.localizedString(for: event.createdAt, relativeTo: Date()))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer(minLength: 0)

                reactionChip(for: event)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .fill(theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .stroke(theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PremiumPressStyle())
    }

    @ViewBuilder
    private func reactionChip(for event: ActivityEvent) -> some View {
        let emoji: String? = {
            switch event.kind {
            case .shiftLogged: return "🔥"
            case .badgeUnlocked: return "🏅"
            case .streakMilestone: return "⚡️"
            case .monthlyMilestone: return "📈"
            case .weeklyMilestone: return "📅"
            case .prestige: return "✨"
            default: return nil
            }
        }()

        if let emoji {
            Text(emoji)
                .font(.system(size: 18))
                .padding(6)
                .background(Circle().fill(theme.cardSecondary))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("Nothing new yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text("Friend events — shifts logged, badges unlocked, milestones — will show up here as they happen.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gentleFadeIn()
    }

    // MARK: - Subscription lifecycle

    private func refreshSubscription() {
        guard let uid = authService.user?.uid else {
            feed.stopListening()
            return
        }
        feed.startListening(
            uid: uid,
            friendUids: friendsService.friends.map(\.uid)
        )
    }
}

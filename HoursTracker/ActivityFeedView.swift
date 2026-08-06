import SwiftUI

// MARK: - Inline activity feed (Phase 6)
//
// Reverse-chronological list of recent activity from the user and their
// friends, embedded directly in the Friends hub's Activity segment (it was
// previously a separate pushed screen). Reads from `ActivityFeedService.events`
// which is kept fresh by per-author snapshot listeners; this view is a thin
// presentation layer and owns only the subscription lifecycle.

struct ActivityFeedInlineSection: View {

    @ObservedObject var feed: ActivityFeedService
    @ObservedObject var friendsService: FriendsService
    @EnvironmentObject private var authService: AuthService

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        content
            .onAppear {
                refreshSubscription()
            }
            .onChange(of: authService.user?.uid) { _, _ in
                refreshSubscription()
            }
            .onChange(of: friendsService.friends.map { "\($0.uid):\($0.weeklyHours):\($0.totalHours)" }) { _, _ in
                refreshSubscription()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let error = feed.errorMessage, feed.events.isEmpty {
            AppErrorState(title: "Couldn't load activity", message: error) {
                refreshSubscription()
            }
            .frame(minHeight: 220)
        } else if feed.isLoading && feed.events.isEmpty {
            AppLoadingState(message: "Catching up on friends…")
                .frame(minHeight: 220)
        } else if feed.events.isEmpty {
            AppEmptyState(
                icon: "sparkles",
                title: "Nothing new yet",
                message: "Friend events — shifts logged, badges unlocked, milestones — will show up here as they happen."
            )
        } else {
            eventList
        }
    }

    /// One quiet card containing every event row, separated by hairlines.
    private var eventList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(feed.events.enumerated()), id: \.element.id) { index, event in
                eventRow(event)
                if index < feed.events.count - 1 {
                    Divider()
                        .overlay(AppColors.stroke)
                        .padding(.leading, 66)
                }
            }
        }
        .animation(nil, value: feed.events.map(\.id))
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.stroke, lineWidth: 0.5)
        )
    }

    private func eventRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatarView(
                    name: event.authorDisplayName,
                    size: 40,
                    photoURL: photoURL(for: event.authorUid),
                    uid: event.authorUid
                )
                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.15))
                        .background(Circle().fill(AppColors.bg))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(AppColors.card, lineWidth: 1.5))
                    Image(systemName: event.iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppColors.accent)
                }
                .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                (Text(event.authorDisplayName)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.text)
                + Text(" ")
                + Text(event.body)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundColor(AppColors.text))
                    .lineLimit(2)

                Text(relativeFormatter.localizedString(for: event.createdAt, relativeTo: Date()))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppColors.faint)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func photoURL(for uid: String) -> String? {
        friendsService.friends.first { $0.uid == uid }?.profilePhotoURL
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

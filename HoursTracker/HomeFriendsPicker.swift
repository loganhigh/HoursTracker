import SwiftUI
import Combine

// MARK: - Home friends visibility

/// Which friends the HOME card shows. A device-local display preference: it
/// never touches the friendship itself, and the Friends tab still lists
/// everyone. Default is everyone visible, so the card behaves exactly as
/// before until someone hides a row.
@MainActor
final class HomeFriendsFilter: ObservableObject {
    static let shared = HomeFriendsFilter()
    private static let key = "home_friends_hidden_uids_v1"

    @Published private(set) var hiddenUids: Set<String>

    private init() {
        hiddenUids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isVisible(_ uid: String) -> Bool { !hiddenUids.contains(uid) }

    func setVisible(_ visible: Bool, uid: String) {
        if visible { hiddenUids.remove(uid) } else { hiddenUids.insert(uid) }
        UserDefaults.standard.set(Array(hiddenUids), forKey: Self.key)
    }
}

/// The toggle list behind the Home card's slider button: every friend, each
/// with a switch for whether they appear on the Home card.
struct HomeFriendsPickerSheet: View {
    @ObservedObject var friendsService: FriendsService
    @ObservedObject private var filter = HomeFriendsFilter.shared
    @Environment(\.dismiss) private var dismiss

    private var sortedFriends: [FriendProfile] {
        friendsService.friends.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedFriends) { friend in
                        Toggle(isOn: Binding(
                            get: { filter.isVisible(friend.uid) },
                            set: { visible in
                                Haptics.lightTap()
                                filter.setVisible(visible, uid: friend.uid)
                            }
                        )) {
                            HStack(spacing: AppSpacing.sm) {
                                ProfileAvatarView(
                                    name: friend.displayName,
                                    size: 34,
                                    photoURL: friend.profilePhotoURL,
                                    uid: friend.uid
                                )
                                .ascendedAvatarRing(prestige: friend.prestige, diameter: 34, inset: 1.5)
                                PrestigeNameText(name: friend.displayName, prestige: friend.prestige, uid: friend.uid)
                                    .appText(.body)
                                    .lineLimit(1)
                                if VerifiedTracker.isVerified(reviewed: friend.hasReviewedApp) {
                                    VerifiedBadgeView(variant: .static, size: 12)
                                }
                            }
                        }
                        .tint(AppColors.accent)
                        .listRowBackground(AppColors.card.opacity(0.55))
                    }
                } footer: {
                    Text("Only changes who shows on your Home screen. Everyone stays in your Friends tab, and nobody is notified.")
                        .foregroundStyle(AppColors.faint)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Friends on Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

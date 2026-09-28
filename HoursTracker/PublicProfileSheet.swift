import SwiftUI
import FirebaseFirestore

// MARK: - Public profile (global leaderboard glimpse)
//
// Opened by tapping any row or podium slot on the global board. A deliberate
// GLIMPSE for strangers: identity, prestige, level, what they do, and — only
// when they share them — lifetime hours, best streak, and a few top badges.
//
// Never shown here, even though publicProfiles carries some of it: company
// name, company start date / tenure, weekly / monthly / cheque hours, days
// worked, last shift time, pay, friend code. The sheet is view-only — no
// friend-request action. Friends get a link through to the full friend view.

/// The slice of `publicProfiles/{uid}` this sheet is allowed to read.
struct PublicProfileGlimpse: Equatable {
    var username: String
    var equippedTitle: String
    var level: Int
    var prestige: Int
    var totalHours: Double
    var bestStreak: Int
    var badgeCount: Int
    var topBadges: [SharedBadgeSummary]
    var shareHours: Bool
    var shareBadges: Bool

    static func parse(_ data: [String: Any]) -> PublicProfileGlimpse {
        let privacy = SocialPrivacyFlags.from(firestore: data["privacy"] as? [String: Any])
        let badges: [SharedBadgeSummary] = (data["unlockedBadgeSummaries"] as? [[String: Any]] ?? [])
            .compactMap { dict in
                guard let name = dict["name"] as? String,
                      let icon = dict["icon"] as? String else { return nil }
                return SharedBadgeSummary(
                    icon: icon,
                    name: name,
                    detail: dict["detail"] as? String ?? "",
                    isLegend: dict["isLegend"] as? Bool ?? false,
                    order: number(dict["order"]).map(Int.init) ?? 0
                )
            }
        let title: String = {
            let admin = (data["adminEquippedTitle"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return admin.isEmpty ? (data["equippedTitle"] as? String ?? "") : admin
        }()
        return PublicProfileGlimpse(
            username: Username.normalize(data["username"] as? String ?? ""),
            equippedTitle: title.strippingWrappingQuotes,
            level: Int(number(data["level"]) ?? 0),
            prestige: Int(number(data["prestige"]) ?? 0),
            totalHours: number(data["totalHours"]) ?? 0,
            bestStreak: Int(number(data["bestStreak"]) ?? 0),
            badgeCount: max(badges.count, Int(number(data["badgeCount"]) ?? 0)),
            // Highest `order` = rarest / most recent — the three worth showing.
            topBadges: Array(badges.sorted { $0.order > $1.order }.prefix(3)),
            shareHours: privacy.shareHours,
            shareBadges: privacy.shareBadges
        )
    }

    private static func number(_ raw: Any?) -> Double? {
        if let v = raw as? Double { return v }
        if let v = raw as? Int { return Double(v) }
        if let v = raw as? Int64 { return Double(v) }
        if let v = raw as? NSNumber { return v.doubleValue }
        return nil
    }
}

struct PublicProfileSheet: View {
    let tracker: TopTracker
    let currentUid: String?

    @ObservedObject private var friendsService = FriendsService.shared
    @State private var glimpse: PublicProfileGlimpse?
    @State private var didFail = false

    private var isMe: Bool { tracker.uid == currentUid }
    private var isFriend: Bool { friendsService.friends.contains { $0.uid == tracker.uid } }

    private var prestige: Int { glimpse?.prestige ?? tracker.prestige }
    private var level: Int { max(glimpse?.level ?? tracker.level, 1) }
    private var tier: PrestigeTheme.Tier { PrestigeTheme.tier(for: prestige) }
    private var accent: Color { prestige > 0 ? tier.primary : AppColors.accent }

    /// The board already carries hours; the doc refines them. A board row is
    /// only ever someone sharing hours, so absent a doc they're shareable.
    private var sharesHours: Bool { glimpse?.shareHours ?? (tracker.hours > 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    identityHeader
                    prestigeCard
                    statsStrip
                    if let glimpse, glimpse.shareBadges, !glimpse.topBadges.isEmpty {
                        badgesCard(glimpse.topBadges)
                    }
                    relationshipFooter
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    // MARK: - Identity

    private var identityHeader: some View {
        VStack(spacing: 8) {
            ProfileAvatarView(
                name: tracker.name,
                size: 76,
                photoURL: tracker.photoURL,
                uid: tracker.uid,
                showsAccentRing: false
            )
            .overlay(Circle().stroke(accent.opacity(tier.isLegend ? 0 : 0.75), lineWidth: 2).padding(-4))
            .ascendedAvatarRing(prestige: prestige, diameter: 76, inset: 4)

            HStack(spacing: 5) {
                PrestigeNameText(
                    name: handle,
                    prestige: prestige,
                    font: .system(size: 20, weight: .bold, design: .rounded)
                )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if VerifiedTracker.isVerified(reviewed: tracker.hasReviewedApp) {
                    VerifiedBadgeView(variant: .shimmer, size: 17)
                }
                if let flag = CountryFlag.emoji(for: CountryFlag.leaderboardCode(
                    trackerUid: tracker.uid,
                    serverCode: tracker.countryCode,
                    currentUid: currentUid
                )) {
                    Text(flag).font(.system(size: 17))
                }
                if isMe { YouChip() }
            }

            if let title = glimpse.flatMap({ $0.shareBadges && !$0.equippedTitle.isEmpty ? $0.equippedTitle : nil }) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
            }

            if !tracker.occupation.isEmpty {
                Label(tracker.occupation, systemImage: "briefcase.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "@username" once claimed; the board's first-name fallback otherwise.
    private var handle: String {
        if let username = glimpse?.username, !username.isEmpty { return "@\(username)" }
        return tracker.name
    }

    // MARK: - Prestige

    private var prestigeCard: some View {
        HStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: tier.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: tier.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tier.onPrimary)
            }
            .frame(width: 48, height: 48)
            .shadow(color: tier.primary.opacity(0.35), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(prestige > 0 ? "Prestige \(prestige)" : "No prestige yet")
                    .appText(.eyebrow)
                    .foregroundStyle(accent)
                Text(tier.name)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.text)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("LEVEL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.faint)
                Text("\(level)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(accent.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stats (privacy-gated)

    private var statsStrip: some View {
        HStack(spacing: 0) {
            if sharesHours {
                statTile(icon: "clock.fill", value: GlobalHoursFormat.hours(glimpse?.totalHours ?? tracker.hours), label: "Lifetime")
                divider
                statTile(icon: "flame.fill", value: glimpse.map { "\($0.bestStreak)d" } ?? "—", label: "Best streak")
            } else {
                statTile(icon: "eye.slash.fill", value: "Hidden", label: "Hours hidden")
            }
            if glimpse?.shareBadges != false {
                divider
                statTile(icon: "rosette", value: glimpse.map { "\($0.badgeCount)" } ?? "—", label: "Badges")
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 0.5)
                )
        )
    }

    private var divider: some View {
        Rectangle().fill(AppColors.stroke).frame(width: 0.5, height: 34)
    }

    private func statTile(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent)
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.faint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Badges

    private func badgesCard(_ badges: [SharedBadgeSummary]) -> some View {
        SectionCard(title: "Top badges", subtitle: nil, trailing: nil, centerHeader: true) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(badges) { badge in
                    FriendBadgeTile(badge: badge, tint: accent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var relationshipFooter: some View {
        if isMe {
            footerNote(icon: "person.crop.circle", text: "This is how others see you on the board")
        } else if isFriend {
            NavigationLink {
                FriendProfileDetailView(friendUid: tracker.uid, friendsService: friendsService)
            } label: {
                Label("Friends • View full profile", systemImage: "person.2.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { Haptics.lightTap() })
        } else if didFail {
            footerNote(icon: "wifi.exclamationmark", text: "Couldn't load everything — showing board details")
        }
    }

    private func footerNote(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(AppColors.faint)
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.xs)
    }

    // MARK: - Load

    /// One read of the public doc for the fields the board row doesn't carry
    /// (title, badges, best streak, privacy). Rules allow any signed-in read.
    private func load() async {
        guard glimpse == nil else { return }
        do {
            let snap = try await Firestore.firestore()
                .collection("publicProfiles").document(tracker.uid).getDocument()
            guard let data = snap.data() else { didFail = true; return }
            withAnimation(AppMotion.Spring.snappy) { glimpse = .parse(data) }
        } catch {
            didFail = true
        }
    }
}

// MARK: - Board row press style

/// Pressed state for tappable board rows: a faint wash plus a slight scale,
/// so the row reads as a button without looking like one at rest.
struct BoardRowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.text.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(AppMotion.Spring.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

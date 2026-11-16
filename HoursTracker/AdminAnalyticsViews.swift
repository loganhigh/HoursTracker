import SwiftUI
import FirebaseFunctions

// MARK: - Admin analytics
//
// The command-center half of the admin console: models for the single
// `adminAnalytics` payload, the compact overview chip row, and the four
// insight screens (Top Active, User Analytics, New Users, At Risk). All of it
// renders from ONE callable response — the client never scans collections,
// and nothing here weakens security rules (every read happens server-side
// behind the admin-uid check).
//
// Metrics shown are only ones the backend genuinely records. Week-one
// retention is counted server-side from the shifts each new account logged;
// the User Analytics screen itself lives in AdminUserAnalyticsScreen.swift.

// MARK: Models

struct AdminOverviewStats {
    var totalUsers = 0
    var activeToday = 0
    var active7d = 0
    var active30d = 0
    var newToday = 0
    var new7d = 0
    var new30d = 0
    var usersLoggedToday = 0
    var shiftsThisWeek = 0
    var hoursThisWeek = 0.0
    var new7dDeltaPct: Int?

    nonisolated init() {}

    nonisolated static func parse(_ dict: [String: Any]) -> AdminOverviewStats {
        func int(_ key: String) -> Int {
            (dict[key] as? Int) ?? (dict[key] as? NSNumber)?.intValue ?? 0
        }
        var stats = AdminOverviewStats()
        stats.totalUsers = int("totalUsers")
        stats.activeToday = int("activeToday")
        stats.active7d = int("active7d")
        stats.active30d = int("active30d")
        stats.newToday = int("newToday")
        stats.new7d = int("new7d")
        stats.new30d = int("new30d")
        stats.usersLoggedToday = int("usersLoggedToday")
        stats.shiftsThisWeek = int("shiftsThisWeek")
        stats.hoursThisWeek = (dict["hoursThisWeek"] as? Double)
            ?? (dict["hoursThisWeek"] as? NSNumber)?.doubleValue ?? 0
        if dict["new7dDeltaPct"] != nil, !(dict["new7dDeltaPct"] is NSNull) {
            stats.new7dDeltaPct = (dict["new7dDeltaPct"] as? Int)
                ?? (dict["new7dDeltaPct"] as? NSNumber)?.intValue
        }
        return stats
    }
}

struct AdminInsightUser: Identifiable {
    let uid: String
    let displayName: String
    let photoURL: String?
    let level: Int
    let prestige: Int
    let verified: Bool
    let weeklyHours: Double
    let weeklyShifts: Int
    let monthHours: Double
    let totalHours: Double
    let currentStreak: Int
    let lastActiveAt: Date?
    let lastShiftAt: Date?
    let createdAt: Date?
    /// 0–100 engagement score (server-computed; recency-weighted).
    var score: Int = 0
    /// At-risk extras.
    var inactiveDays: Int?
    var reasons: [String] = []
    /// Last win-back push (automatic or manual), and whether a manual nudge
    /// is allowed now (once a week per user).
    var lastNudgeAt: Date?
    var canNudge = true
    /// Latest app open or logged shift (activity-breakdown lists only).
    var lastTouchAt: Date?
    /// Thank-you push state (Top Active only): last sent, how many ever,
    /// whether one can go now, why not ("cooldown" / "inactive"), and when
    /// the 90-day cap lifts.
    var lastThanksAt: Date?
    var thanksCount = 0
    var canThank = false
    var thankBlockedReason: String?
    var nextThanksAt: Date?

    var id: String { uid }

    nonisolated static func parse(_ dict: [String: Any]) -> AdminInsightUser {
        func int(_ key: String) -> Int {
            (dict[key] as? Int) ?? (dict[key] as? NSNumber)?.intValue ?? 0
        }
        func double(_ key: String) -> Double {
            (dict[key] as? Double) ?? (dict[key] as? NSNumber)?.doubleValue ?? 0
        }
        func date(_ key: String) -> Date? {
            let ms = (dict[key] as? Double) ?? (dict[key] as? NSNumber)?.doubleValue
            guard let ms, ms > 0 else { return nil }
            return Date(timeIntervalSince1970: ms / 1000)
        }
        var user = AdminInsightUser(
            uid: dict["uid"] as? String ?? "",
            displayName: dict["displayName"] as? String ?? "Worker",
            photoURL: dict["photoURL"] as? String,
            level: int("level"),
            prestige: int("prestige"),
            verified: dict["hasReviewedApp"] as? Bool ?? false,
            weeklyHours: double("weeklyHours"),
            weeklyShifts: int("weeklyShifts"),
            monthHours: double("monthHours"),
            totalHours: double("totalHours"),
            currentStreak: int("currentStreak"),
            lastActiveAt: date("lastActiveAt"),
            lastShiftAt: date("lastShiftMs"),
            createdAt: date("createdAt")
        )
        user.score = int("score")
        if dict["inactiveDays"] != nil { user.inactiveDays = int("inactiveDays") }
        user.reasons = dict["reasons"] as? [String] ?? []
        user.lastNudgeAt = date("lastNudgeMs")
        user.canNudge = dict["canNudge"] as? Bool ?? true
        user.lastTouchAt = date("lastTouchMs")
        user.lastThanksAt = date("lastThanksMs")
        user.thanksCount = int("thanksCount")
        user.canThank = dict["canThank"] as? Bool ?? false
        user.thankBlockedReason = dict["thankBlockedReason"] as? String
        user.nextThanksAt = date("nextThanksMs")
        return user
    }
}

struct AdminGrowthBucket: Identifiable {
    let dayStart: Date
    let count: Int
    var id: Date { dayStart }
}

struct AdminDailyHistory: Identifiable {
    let at: Date
    let activeToday: Int
    let usersLoggedToday: Int
    var id: Date { at }
}

/// Active vs inactive buckets from the server (see activityBucket in
/// functions/src/admin/analytics.js).
enum AdminActivityBucket: String, CaseIterable, Identifiable {
    case active, quiet, gone, never
    var id: String { rawValue }
}

struct AdminActivityBreakdown {
    var counts: [AdminActivityBucket: Int] = [:]
    var lists: [AdminActivityBucket: [AdminInsightUser]] = [:]
    var boardCutoffDays = 30

    nonisolated init() {}

    var total: Int { counts.values.reduce(0, +) }
    func count(_ b: AdminActivityBucket) -> Int { counts[b] ?? 0 }
}

/// One weekly signup cohort's first-week outcome.
struct AdminCohort: Identifiable {
    let weekStart: Date
    let signups: Int
    let loggedAny: Int
    let hitGoal: Int
    let activeNow: Int
    /// false while the cohort's newest accounts are still in week one.
    let complete: Bool
    var id: Date { weekStart }

    var goalRate: Double { signups > 0 ? Double(hitGoal) / Double(signups) : 0 }
}

struct AdminAnalyticsPayload {
    let overview: AdminOverviewStats
    let topActive: [AdminInsightUser]
    let atRisk: [AdminInsightUser]
    let newUsers: [AdminInsightUser]
    let growth: [AdminGrowthBucket]
    let history: [AdminDailyHistory]
    var activity = AdminActivityBreakdown()
    var cohorts: [AdminCohort] = []
    let generatedAt: Date

    nonisolated static func parse(_ dict: [String: Any]) -> AdminAnalyticsPayload {
        let users: ([Any]?) -> [AdminInsightUser] = { raw in
            (raw ?? []).compactMap { ($0 as? [String: Any]).map(AdminInsightUser.parse) }
        }
        let growth: [AdminGrowthBucket] = ((dict["growth"] as? [Any]) ?? []).compactMap { raw in
            guard let d = raw as? [String: Any],
                  let ms = (d["dayStartMs"] as? Double) ?? (d["dayStartMs"] as? NSNumber)?.doubleValue
            else { return nil }
            let count = (d["count"] as? Int) ?? (d["count"] as? NSNumber)?.intValue ?? 0
            return AdminGrowthBucket(dayStart: Date(timeIntervalSince1970: ms / 1000), count: count)
        }
        let history: [AdminDailyHistory] = ((dict["history"] as? [Any]) ?? []).compactMap { raw in
            guard let d = raw as? [String: Any],
                  let ms = (d["atMs"] as? Double) ?? (d["atMs"] as? NSNumber)?.doubleValue
            else { return nil }
            return AdminDailyHistory(
                at: Date(timeIntervalSince1970: ms / 1000),
                activeToday: (d["activeToday"] as? Int) ?? (d["activeToday"] as? NSNumber)?.intValue ?? 0,
                usersLoggedToday: (d["usersLoggedToday"] as? Int) ?? (d["usersLoggedToday"] as? NSNumber)?.intValue ?? 0
            )
        }
        func num(_ any: Any?) -> Int { (any as? Int) ?? (any as? NSNumber)?.intValue ?? 0 }
        var activity = AdminActivityBreakdown()
        if let raw = dict["activity"] as? [String: Any] {
            let counts = raw["counts"] as? [String: Any] ?? [:]
            let lists = raw["lists"] as? [String: Any] ?? [:]
            for bucket in AdminActivityBucket.allCases {
                activity.counts[bucket] = num(counts[bucket.rawValue])
                activity.lists[bucket] = users(lists[bucket.rawValue] as? [Any])
            }
            if raw["boardCutoffDays"] != nil { activity.boardCutoffDays = num(raw["boardCutoffDays"]) }
        }
        let cohorts: [AdminCohort] = ((dict["cohorts"] as? [Any]) ?? []).compactMap { raw in
            guard let d = raw as? [String: Any],
                  let ms = (d["weekStartMs"] as? Double) ?? (d["weekStartMs"] as? NSNumber)?.doubleValue
            else { return nil }
            return AdminCohort(
                weekStart: Date(timeIntervalSince1970: ms / 1000),
                signups: num(d["signups"]),
                loggedAny: num(d["loggedAny"]),
                hitGoal: num(d["hitGoal"]),
                activeNow: num(d["activeNow"]),
                complete: d["complete"] as? Bool ?? true
            )
        }
        var payload = AdminAnalyticsPayload(
            overview: AdminOverviewStats.parse(dict["overview"] as? [String: Any] ?? [:]),
            topActive: users(dict["topActive"] as? [Any]),
            atRisk: users(dict["atRisk"] as? [Any]),
            newUsers: users(dict["newUsers"] as? [Any]),
            growth: growth,
            history: history,
            generatedAt: Date()
        )
        payload.activity = activity
        payload.cohorts = cohorts
        return payload
    }
}

// MARK: Shared formatting

enum AdminFormat {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func lastActive(_ date: Date?) -> String {
        guard let date else { return "Never active" }
        return "Active \(relative.localizedString(for: date, relativeTo: Date()))"
    }

    static func joined(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Overview chip row

/// Compact, horizontally scrollable stat chips — deliberately small so the
/// analytics never crowd the user list they sit above.
struct AdminOverviewRow: View {
    let stats: AdminOverviewStats
    /// Version-adoption chip, computed client-side from the loaded user list
    /// (see AdminPanelView.latestVersionStat). nil until users have loaded or
    /// when no user has reported a version yet.
    var versionStat: (version: String, onLatest: Int, total: Int)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("\(stats.totalUsers)", "Users")
                if let versionStat {
                    chip("\(versionStat.onLatest)/\(versionStat.total)", "On v\(versionStat.version)")
                }
                chip("\(stats.activeToday)", "Active Today")
                chip("\(stats.active7d)", "Active 7D")
                chip("\(stats.active30d)", "Active 30D")
                chip("+\(stats.new7d)", "New 7D", delta: stats.new7dDeltaPct)
                chip("\(stats.usersLoggedToday)", "Logged Today")
                chip("\(stats.shiftsThisWeek)", "Shifts This Wk")
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ value: String, _ label: String, delta: Int? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.text)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.faint)
                .lineLimit(1)
            if let delta {
                Text(delta >= 0 ? "+\(delta)% vs last wk" : "\(delta)% vs last wk")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(delta >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.card2)
        )
    }
}

// MARK: - Shared insight row

struct AdminInsightUserRow: View {
    let user: AdminInsightUser
    var rank: Int?
    var detail: String
    var subDetail: String?
    var trailing: (value: String, tint: Color)?

    var body: some View {
        HStack(spacing: 10) {
            if let rank {
                Text("\(rank)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.faint)
                    .frame(width: 24, alignment: .leading)
            }

            ProfileAvatarView(name: user.displayName, size: 36, photoURL: user.photoURL, uid: user.uid)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(user.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)
                        .lineLimit(1)
                    if user.verified {
                        VerifiedBadgeView(variant: .static, size: 12)
                    }
                    if user.level > 0 {
                        Text(user.prestige > 0 ? "L\(user.level)·P\(user.prestige)" : "L\(user.level)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                }
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .lineLimit(1)
                if let subDetail {
                    Text(subDetail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            if let trailing {
                Text(trailing.value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(trailing.tint)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Tiny capsule bar chart — no axes, no labels, just the shape of the data.
struct AdminMiniBarChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 1)
            let spacing: CGFloat = values.count > 40 ? 1 : 2
            let barWidth = max(1, (geo.size.width - spacing * CGFloat(max(values.count - 1, 0))) / CGFloat(max(values.count, 1)))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule(style: .continuous)
                        .fill(AppTheme.Colors.accent.opacity(value > 0 ? 0.9 : 0.15))
                        .frame(width: barWidth, height: max(2, CGFloat(value / maxValue) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 56)
    }
}

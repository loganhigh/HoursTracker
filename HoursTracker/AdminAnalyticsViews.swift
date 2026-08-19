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
// Metrics shown are only ones the backend genuinely records. There is no
// retention section and no per-period XP because no historical data exists
// for them — the daily `adminDaily` snapshot (written by dailyStatsRefresh)
// starts accumulating engagement history from the day this ships.

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

struct AdminAnalyticsPayload {
    let overview: AdminOverviewStats
    let topActive: [AdminInsightUser]
    let atRisk: [AdminInsightUser]
    let newUsers: [AdminInsightUser]
    let growth: [AdminGrowthBucket]
    let history: [AdminDailyHistory]
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
        return AdminAnalyticsPayload(
            overview: AdminOverviewStats.parse(dict["overview"] as? [String: Any] ?? [:]),
            topActive: users(dict["topActive"] as? [Any]),
            atRisk: users(dict["atRisk"] as? [Any]),
            newUsers: users(dict["newUsers"] as? [Any]),
            growth: growth,
            history: history,
            generatedAt: Date()
        )
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("\(stats.totalUsers)", "Users")
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

// MARK: - Top Active Users

struct AdminTopActiveView: View {
    let analytics: AdminAnalyticsPayload

    /// Honest ranges only: per-day hours aren't stored per user, so there is
    /// no "Today" tab — This Week / This Month / All Time are the periods the
    /// server genuinely tracks.
    enum Range: String, CaseIterable {
        case week = "This Week"
        case month = "This Month"
        case allTime = "All Time"
    }

    @State private var range: Range = .week

    private var ranked: [AdminInsightUser] {
        switch range {
        case .week:
            // Score already weights the present hard.
            return analytics.topActive
        case .month:
            return analytics.topActive.sorted { $0.monthHours > $1.monthHours }
        case .allTime:
            return analytics.topActive.sorted { $0.totalHours > $1.totalHours }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, user in
                    AdminInsightUserRow(
                        user: user,
                        rank: index + 1,
                        detail: detail(for: user),
                        subDetail: AdminFormat.lastActive(user.lastActiveAt),
                        trailing: ("\(user.score)", scoreTint(user.score))
                    )
                    .listRowBackground(AppTheme.Colors.card)
                }
            } footer: {
                Text("Activity score (0–100) weights the present: recency, shifts and hours this week, and current streak. Lifetime hours deliberately don't count — the score answers \"who is using Hour Tracker right now\".")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Top Active Users")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(for user: AdminInsightUser) -> String {
        var parts: [String]
        switch range {
        case .week:
            parts = [AppTheme.Format.hours(user.weeklyHours), "\(user.weeklyShifts) shifts"]
        case .month:
            parts = [AppTheme.Format.hours(user.monthHours) + " this month"]
        case .allTime:
            parts = [AppTheme.Format.hours(user.totalHours) + " lifetime"]
        }
        if user.currentStreak > 0 { parts.append("\(user.currentStreak) day streak") }
        return parts.joined(separator: " • ")
    }

    private func scoreTint(_ score: Int) -> Color {
        if score >= 70 { return AppTheme.Colors.success }
        if score >= 35 { return AppTheme.Colors.accent }
        return AppTheme.Colors.faint
    }
}

// MARK: - User Analytics

struct AdminUserAnalyticsView: View {
    let analytics: AdminAnalyticsPayload

    enum GrowthRange: String, CaseIterable {
        case week = "7D", month = "30D", quarter = "90D"
        var days: Int { self == .week ? 7 : self == .month ? 30 : 90 }
    }

    @State private var growthRange: GrowthRange = .month

    var body: some View {
        let stats = analytics.overview
        List {
            Section {
                statRow("Total users", "\(stats.totalUsers)")
                statRow("New today", "+\(stats.newToday)")
                statRow("New this week", "+\(stats.new7d)",
                        delta: stats.new7dDeltaPct.map { "\($0 >= 0 ? "+" : "")\($0)% vs last week" })
                statRow("New this month", "+\(stats.new30d)")

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Range", selection: $growthRange) {
                        ForEach(GrowthRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    AdminMiniBarChart(
                        values: analytics.growth.suffix(growthRange.days).map { Double($0.count) }
                    )
                    Text("Signups per day")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.faint)
                }
                .listRowBackground(AppTheme.Colors.card)
            } header: {
                Text("User Growth")
            }
            .listRowBackground(AppTheme.Colors.card)

            Section {
                statRow("Daily active users", "\(stats.activeToday)")
                statRow("Weekly active users", "\(stats.active7d)")
                statRow("Monthly active users", "\(stats.active30d)")
                statRow("Users who logged today", "\(stats.usersLoggedToday)")
                statRow("Shifts this week", "\(stats.shiftsThisWeek)")
                statRow("Hours this week", AppTheme.Format.hours(stats.hoursThisWeek))

                if analytics.history.count >= 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        AdminMiniBarChart(values: analytics.history.map { Double($0.activeToday) })
                        Text("Daily active users — last \(analytics.history.count) days")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.faint)
                    }
                    .listRowBackground(AppTheme.Colors.card)
                }
            } header: {
                Text("Engagement")
            } footer: {
                analytics.history.count < 2
                    ? Text("Daily engagement history starts accumulating from today's snapshot — charts appear once a few days exist.")
                    : Text("")
            }
            .listRowBackground(AppTheme.Colors.card)

            Section {
                Text("Not tracked yet — retention needs per-user return history, which the backend doesn't record. Nothing here is estimated.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.faint)
                    .listRowBackground(AppTheme.Colors.card)
            } header: {
                Text("Retention")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("User Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ label: String, _ value: String, delta: String? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                if let delta {
                    Text(delta)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(delta.hasPrefix("+") ? AppTheme.Colors.success : AppTheme.Colors.danger)
                }
            }
        }
        .listRowBackground(AppTheme.Colors.card)
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

// MARK: - New Users

struct AdminNewUsersView: View {
    let analytics: AdminAnalyticsPayload

    enum Range: String, CaseIterable {
        case today = "Today", week = "7D", month = "30D"
        var days: Double { self == .today ? 1 : self == .week ? 7 : 30 }
    }

    @State private var range: Range = .week

    private var filtered: [AdminInsightUser] {
        let cutoff = Date().addingTimeInterval(-range.days * 86400)
        return analytics.newUsers.filter { ($0.createdAt ?? .distantPast) >= cutoff }
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if filtered.isEmpty {
                    Text("No signups in this range.")
                        .foregroundStyle(AppTheme.Colors.faint)
                        .listRowBackground(AppTheme.Colors.card)
                }
                ForEach(filtered) { user in
                    AdminInsightUserRow(
                        user: user,
                        detail: "Joined \(AdminFormat.joined(user.createdAt)) • \(AppTheme.Format.hours(user.totalHours)) • \(user.weeklyShifts) shifts this wk",
                        subDetail: AdminFormat.lastActive(user.lastActiveAt),
                        trailing: nil
                    )
                    .listRowBackground(AppTheme.Colors.card)
                }
            } footer: {
                Text("Whether signups become users: hours and shifts show who actually started logging after joining.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("New Users")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - At Risk Users

struct AdminAtRiskView: View {
    let analytics: AdminAnalyticsPayload

    enum Threshold: String, CaseIterable {
        case d3 = "3+ days", d7 = "7+ days", d14 = "14+ days", d30 = "30+ days"
        var days: Int { self == .d3 ? 3 : self == .d7 ? 7 : self == .d14 ? 14 : 30 }
    }

    @State private var threshold: Threshold = .d3

    private var filtered: [AdminInsightUser] {
        analytics.atRisk.filter { ($0.inactiveDays ?? 0) >= threshold.days }
    }

    var body: some View {
        List {
            Section {
                Picker("Inactive", selection: $threshold) {
                    ForEach(Threshold.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if filtered.isEmpty {
                    Text("Nobody at risk in this range — everyone previously active has been on recently.")
                        .foregroundStyle(AppTheme.Colors.faint)
                        .listRowBackground(AppTheme.Colors.card)
                }
                ForEach(filtered) { user in
                    AdminInsightUserRow(
                        user: user,
                        detail: "Previously active • \(AppTheme.Format.hours(user.totalHours)) lifetime",
                        subDetail: user.reasons.joined(separator: " • "),
                        trailing: user.inactiveDays.map { ("\($0)d", AppTheme.Colors.warning) }
                    )
                    .listRowBackground(AppTheme.Colors.card)
                }
            } footer: {
                Text("Users with real history (10+ hours or a 3+ day best streak) who have gone quiet. Reasons come from recorded behaviour only.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("At Risk Users")
        .navigationBarTitleDisplayMode(.inline)
    }
}

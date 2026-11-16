import SwiftUI

// MARK: - User Analytics (admin)
//
// One scrolling page of cards, read top to bottom as a story:
//   1. Who's still here: active / quiet / gone / never logged, each tappable.
//   2. The pulse: daily + weekly actives, logged today, hours this week.
//   3. Week-one habit: per weekly signup cohort, how many logged on 3+ days
//      in their first week (the habit that predicts who stays).
//   4. Growth: signups per day.
// Everything comes from the single adminAnalytics payload.

extension AdminActivityBucket {
    var title: String {
        switch self {
        case .active: return "Active"
        case .quiet: return "Quiet"
        case .gone: return "Gone"
        case .never: return "Never logged"
        }
    }

    var detail: String {
        switch self {
        case .active: return "Opened the app or logged in the last 7 days"
        case .quiet: return "Last seen 7 to 30 days ago"
        case .gone: return "Nothing for 30+ days. Off the leaderboard until they return"
        case .never: return "Signed up but never logged a shift"
        }
    }

    var color: Color {
        switch self {
        case .active: return AppTheme.Colors.success
        case .quiet: return AppTheme.Colors.warning
        case .gone: return AppTheme.Colors.danger
        case .never: return AppTheme.Colors.faint
        }
    }
}

struct AdminUserAnalyticsView: View {
    let analytics: AdminAnalyticsPayload

    enum GrowthRange: String, CaseIterable {
        case week = "7D", month = "30D", quarter = "90D"
        var days: Int { self == .week ? 7 : self == .month ? 30 : 90 }
    }

    @State private var growthRange: GrowthRange = .month

    private var stats: AdminOverviewStats { analytics.overview }
    private var activity: AdminActivityBreakdown { analytics.activity }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                activityCard
                pulseGrid
                cohortCard
                growthCard
                if analytics.history.count >= 2 { historyCard }
                Text("Updated \(analytics.generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.faint)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("User Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 1. Who's still here

    private var activityCard: some View {
        let total = max(activity.total, 1)
        let active = activity.count(.active)
        return card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        eyebrow("Who's still here")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(active)")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.Colors.text)
                            Text("of \(activity.total) active")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.subtext)
                        }
                    }
                    Spacer()
                    Text("\(Int((Double(active) / Double(total) * 100).rounded()))%")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Colors.success)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppTheme.Colors.success.opacity(0.15)))
                }

                segmentedBar(total: total)

                VStack(spacing: 0) {
                    ForEach(AdminActivityBucket.allCases) { bucket in
                        NavigationLink {
                            AdminActivityBucketView(
                                bucket: bucket,
                                users: activity.lists[bucket] ?? [],
                                total: activity.count(bucket)
                            )
                        } label: {
                            bucketRow(bucket, total: total)
                        }
                        .buttonStyle(.plain)
                        if bucket != AdminActivityBucket.allCases.last {
                            Divider().overlay(AppTheme.Colors.stroke)
                        }
                    }
                }
            }
        }
    }

    private func segmentedBar(total: Int) -> some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(AdminActivityBucket.allCases) { bucket in
                    let n = activity.count(bucket)
                    if n > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(bucket.color)
                            .frame(width: max(6, (geo.size.width - 9) * CGFloat(n) / CGFloat(total)))
                    }
                }
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func bucketRow(_ bucket: AdminActivityBucket, total: Int) -> some View {
        let n = activity.count(bucket)
        return HStack(spacing: 12) {
            Circle().fill(bucket.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                Text(bucket.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(n)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.text)
                Text("\(Int((Double(n) / Double(total) * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.faint)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.Colors.faint)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: 2. Pulse

    private var pulseGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("Active today", "\(stats.activeToday)", icon: "sun.max.fill")
            tile("Active this week", "\(stats.active7d)", icon: "calendar")
            tile("Logged today", "\(stats.usersLoggedToday)", icon: "checkmark.circle.fill")
            tile("Hours this week", AppTheme.Format.hours(stats.hoursThisWeek), icon: "clock.fill",
                 footnote: "\(stats.shiftsThisWeek) shifts")
        }
    }

    private func tile(_ label: String, _ value: String, icon: String, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.Colors.accent)
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(footnote.map { "\(label) · \($0)" } ?? label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppTheme.Colors.card))
        .accessibilityElement(children: .combine)
    }

    // MARK: 3. Week-one habit

    private var cohortCard: some View {
        let finished = analytics.cohorts.filter { $0.complete && $0.signups > 0 }
        let signups = finished.reduce(0) { $0 + $1.signups }
        let hit = finished.reduce(0) { $0 + $1.hitGoal }
        let rate = signups > 0 ? Int((Double(hit) / Double(signups) * 100).rounded()) : nil
        let shown = analytics.cohorts.filter { $0.signups > 0 }.reversed()

        return card {
            VStack(alignment: .leading, spacing: 12) {
                eyebrow("Week-one habit")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rate.map { "\($0)%" } ?? "—")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.Colors.text)
                    Text("logged 3+ days in week one")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
                if signups > 0 {
                    Text("\(hit) of \(signups) signups across finished weeks")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                }

                if shown.isEmpty {
                    Text("No signups in the last 8 weeks yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(shown)) { cohortRow($0) }
                    }
                    .padding(.top, 4)
                }

                Text("People who log on 3+ different days in their first week stick around far more often. The Home card nudges new users toward it.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cohortRow(_ c: AdminCohort) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Week of \(c.weekStart.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                if !c.complete {
                    Text("In progress")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.Colors.accent.opacity(0.15)))
                }
                Spacer()
                Text("\(c.hitGoal)/\(c.signups)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Colors.card2)
                    Capsule()
                        .fill(AppTheme.Colors.accent.opacity(0.35))
                        .frame(width: geo.size.width * CGFloat(c.signups > 0 ? Double(c.loggedAny) / Double(c.signups) : 0))
                    Capsule()
                        .fill(AppTheme.Colors.accent)
                        .frame(width: geo.size.width * CGFloat(c.goalRate))
                }
            }
            .frame(height: 8)
            Text("\(c.loggedAny) logged any shift · \(c.activeNow) still active")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.Colors.faint)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 4. Growth

    private var growthCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    eyebrow("Signups")
                    Spacer()
                    if let delta = stats.new7dDeltaPct {
                        Text("\(delta >= 0 ? "+" : "")\(delta)% vs last week")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(delta >= 0 ? AppTheme.Colors.success : AppTheme.Colors.danger)
                    }
                }
                HStack(spacing: 0) {
                    growthStat("Today", stats.newToday)
                    growthStat("7 days", stats.new7d)
                    growthStat("30 days", stats.new30d)
                    growthStat("Total", stats.totalUsers, plus: false)
                }
                Picker("Range", selection: $growthRange) {
                    ForEach(GrowthRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                AdminMiniBarChart(values: analytics.growth.suffix(growthRange.days).map { Double($0.count) })
            }
        }
    }

    private func growthStat(_ label: String, _ value: Int, plus: Bool = true) -> some View {
        VStack(spacing: 2) {
            Text(plus ? "+\(value)" : "\(value)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.text)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.faint)
        }
        .frame(maxWidth: .infinity)
    }

    private var historyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("Daily active, last \(analytics.history.count) days")
                AdminMiniBarChart(values: analytics.history.map { Double($0.activeToday) })
            }
        }
    }

    // MARK: Pieces

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(AppTheme.Colors.faint)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(AppTheme.Colors.card))
    }
}

// MARK: - Bucket list

/// Everyone in one activity bucket, most recently seen first.
struct AdminActivityBucketView: View {
    let bucket: AdminActivityBucket
    let users: [AdminInsightUser]
    let total: Int

    @State private var query = ""

    private var filtered: [AdminInsightUser] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        List {
            Section {
                if filtered.isEmpty {
                    Text(users.isEmpty ? "Nobody here." : "No matches.")
                        .foregroundStyle(AppTheme.Colors.faint)
                        .listRowBackground(AppTheme.Colors.card)
                }
                ForEach(filtered) { user in
                    AdminInsightUserRow(
                        user: user,
                        detail: detail(for: user),
                        subDetail: "Joined \(AdminFormat.joined(user.createdAt))",
                        trailing: nil
                    )
                    .listRowBackground(AppTheme.Colors.card)
                }
            } header: {
                Text(total > users.count ? "\(total) users · showing \(users.count)" : "\(total) users")
            } footer: {
                Text(bucket.detail)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search names")
        .navigationTitle(bucket.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(for user: AdminInsightUser) -> String {
        let seen: String = {
            guard let at = user.lastTouchAt else { return "Never seen" }
            return "Seen \(AdminFormat.relative.localizedString(for: at, relativeTo: Date()))"
        }()
        if bucket == .never { return seen }
        return "\(seen) · \(AppTheme.Format.hours(user.totalHours)) lifetime"
    }
}

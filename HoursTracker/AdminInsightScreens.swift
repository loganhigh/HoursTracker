import SwiftUI
import FirebaseFunctions

// MARK: - New Users + At Risk Users (admin)
//
// Same card language as User Analytics and Top Active Users: a summary card
// with one big number, a segmented range, then everyone in one card.

/// Shared card + eyebrow so the admin insight screens look like one family.
struct AdminInsightCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(AppTheme.Colors.card))
    }
}

struct AdminEyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(AppTheme.Colors.faint)
    }
}

/// Small stat box used in the summary cards.
struct AdminMiniStat: View {
    let value: String
    let label: String
    var tint: Color = AppTheme.Colors.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.Colors.card2))
    }
}

/// Avatar + name line + detail, shared by both lists.
private struct AdminPersonLine: View {
    let user: AdminInsightUser
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            ProfileAvatarView(name: user.displayName, size: 38, photoURL: user.photoURL, uid: user.uid)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(user.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)
                        .lineLimit(1)
                    if user.verified { VerifiedBadgeView(variant: .static, size: 12) }
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
            }
        }
    }
}

private func adminChip(_ text: String, tint: Color) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.15)))
}

// MARK: - New Users

struct AdminNewUsersView: View {
    let analytics: AdminAnalyticsPayload

    enum Range: String, CaseIterable {
        case today = "Today", week = "7D", month = "30D"
        var days: Double { self == .today ? 1 : self == .week ? 7 : 30 }
        var phrase: String { self == .today ? "today" : self == .week ? "this week" : "in 30 days" }
    }

    @State private var range: Range = .week

    private var filtered: [AdminInsightUser] {
        let cutoff = Date().addingTimeInterval(-range.days * 86400)
        return analytics.newUsers.filter { ($0.createdAt ?? .distantPast) >= cutoff }
    }

    private func isLogging(_ u: AdminInsightUser) -> Bool { u.totalHours > 0 || u.lastShiftAt != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                listCard
                Text("Logging = logged at least one shift since joining. The ones who haven't yet are who a first-shift nudge is for.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(AppMotion.Spring.smooth, value: range)
        }
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("New Users")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        let users = filtered
        let logging = users.filter(isLogging).count
        let rate = users.isEmpty ? 0 : Int((Double(logging) / Double(users.count) * 100).rounded())
        let activeRecently = users.filter { ($0.lastActiveAt ?? .distantPast) > Date().addingTimeInterval(-3 * 86400) }.count
        return AdminInsightCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        AdminEyebrow("New trackers")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(users.count)")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.Colors.text)
                                .contentTransition(.numericText())
                            Text("joined \(range.phrase)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.subtext)
                        }
                    }
                    Spacer()
                    if range == .week, let delta = analytics.overview.new7dDeltaPct {
                        adminChip("\(delta >= 0 ? "+" : "")\(delta)% vs last wk",
                                  tint: delta >= 0 ? AppTheme.Colors.success : AppTheme.Colors.warning)
                    }
                }
                HStack(spacing: 10) {
                    AdminMiniStat(value: "\(logging)", label: "logging shifts", tint: AppTheme.Colors.success)
                    AdminMiniStat(value: "\(rate)%", label: "started logging")
                    AdminMiniStat(value: "\(activeRecently)", label: "seen in 3 days")
                }
            }
        }
    }

    private var listCard: some View {
        AdminInsightCard {
            VStack(spacing: 0) {
                if filtered.isEmpty {
                    Text("No signups \(range.phrase).")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, user in
                    HStack(spacing: 8) {
                        AdminPersonLine(user: user, detail: detail(for: user))
                        Spacer(minLength: 4)
                        if isLogging(user) {
                            VStack(alignment: .trailing, spacing: 3) {
                                adminChip("Logging", tint: AppTheme.Colors.success)
                                Text(AppTheme.Format.hours(user.totalHours))
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.Colors.text)
                            }
                        } else {
                            adminChip("No shifts yet", tint: AppTheme.Colors.faint)
                        }
                    }
                    .padding(.vertical, 9)
                    if index < filtered.count - 1 {
                        Divider().overlay(AppTheme.Colors.stroke)
                    }
                }
            }
        }
    }

    private func detail(for user: AdminInsightUser) -> String {
        var parts = ["Joined \(AdminFormat.joined(user.createdAt))"]
        if let seen = user.lastActiveAt {
            parts.append("seen \(seen.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - At Risk Users

struct AdminAtRiskView: View {
    let analytics: AdminAnalyticsPayload
    var passcode = ""

    @State private var nudgedNow: Set<String> = []
    @State private var nudging: String?
    @State private var nudgeError: String?

    enum Threshold: String, CaseIterable {
        case d3 = "3+ days", d7 = "7+ days", d14 = "14+ days", d30 = "30+ days"
        var days: Int { self == .d3 ? 3 : self == .d7 ? 7 : self == .d14 ? 14 : 30 }
    }

    @State private var threshold: Threshold = .d3

    private var filtered: [AdminInsightUser] {
        analytics.atRisk.filter { ($0.inactiveDays ?? 0) >= threshold.days }
    }

    private func canNudge(_ u: AdminInsightUser) -> Bool { u.canNudge && !nudgedNow.contains(u.uid) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                Picker("Inactive", selection: $threshold) {
                    ForEach(Threshold.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                listCard
                Text("People with real history (10+ hours or a 3+ day best streak) who've gone quiet longer than their usual break. Come-back pushes go out automatically at about 7 and 21 days. The bell sends one now: once a week per person.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(AppMotion.Spring.smooth, value: threshold)
        }
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("At Risk Users")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't nudge", isPresented: Binding(
            get: { nudgeError != nil }, set: { if !$0 { nudgeError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(nudgeError ?? "") }
    }

    private var summaryCard: some View {
        let users = filtered
        let hoursAtStake = users.reduce(0) { $0 + $1.totalHours }
        let ready = users.filter(canNudge).count
        let nudgedRecently = users.filter {
            nudgedNow.contains($0.uid) || ($0.lastNudgeAt ?? .distantPast) > Date().addingTimeInterval(-7 * 86400)
        }.count
        return AdminInsightCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    AdminEyebrow("Slipping away")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(users.count)")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.Colors.text)
                            .contentTransition(.numericText())
                        Text("quiet \(threshold.rawValue)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.subtext)
                    }
                }
                HStack(spacing: 10) {
                    AdminMiniStat(value: AppTheme.Format.hours(hoursAtStake), label: "lifetime hours")
                    AdminMiniStat(value: "\(nudgedRecently)", label: "nudged this wk")
                    AdminMiniStat(value: "\(ready)", label: "ready to nudge", tint: AppTheme.Colors.accent)
                }
            }
        }
    }

    private var listCard: some View {
        AdminInsightCard {
            VStack(spacing: 0) {
                if filtered.isEmpty {
                    Text("Nobody at risk in this range. Everyone previously active has been on recently.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, user in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            AdminPersonLine(
                                user: user,
                                detail: "\(AppTheme.Format.hours(user.totalHours)) lifetime"
                            )
                            Spacer(minLength: 4)
                            if let days = user.inactiveDays {
                                adminChip("\(days)d quiet", tint: days >= 21 ? AppTheme.Colors.danger : AppTheme.Colors.warning)
                            }
                            nudgeButton(for: user)
                        }
                        let sub = subDetail(for: user)
                        if !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.faint)
                                .lineLimit(2)
                                .padding(.leading, 48)
                        }
                    }
                    .padding(.vertical, 9)
                    if index < filtered.count - 1 {
                        Divider().overlay(AppTheme.Colors.stroke)
                    }
                }
            }
        }
    }

    private func subDetail(for user: AdminInsightUser) -> String {
        var parts = user.reasons
        if nudgedNow.contains(user.uid) {
            parts.append("Nudged just now")
        } else if let last = user.lastNudgeAt {
            parts.append("Nudged \(last.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private func nudgeButton(for user: AdminInsightUser) -> some View {
        let done = !canNudge(user)
        return Button {
            Task { await nudge(user) }
        } label: {
            Group {
                if nudging == user.uid {
                    ProgressView()
                } else {
                    Image(systemName: done ? "checkmark" : "bell.badge")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .frame(width: 34, height: 34)
            .foregroundStyle(done ? AppTheme.Colors.faint : AppTheme.Colors.accent)
            .background(Circle().fill(AppTheme.Colors.card2))
        }
        .buttonStyle(.plain)
        .disabled(done || nudging != nil)
        .accessibilityLabel(done ? "Nudged this week" : "Nudge \(user.displayName)")
    }

    private func nudge(_ user: AdminInsightUser) async {
        nudging = user.uid
        defer { nudging = nil }
        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("adminSendWinbackNudge")
                .call(["passcode": passcode, "uid": user.uid])
            nudgedNow.insert(user.uid)
            Haptics.success()
        } catch {
            nudgeError = error.localizedDescription
            Haptics.error()
        }
    }
}

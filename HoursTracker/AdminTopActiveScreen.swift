import SwiftUI
import FirebaseFunctions

// MARK: - Top Active Users (admin)
//
// Card layout to match User Analytics:
//   1. Summary: how many power users (score 70+), and the top 50's week.
//   2. The top three, larger.
//   3. Everyone else in one card.
// Each person has a heart button that sends a thank-you push
// (adminSendAppreciation): one per person per 90 days, only while they're
// still active. The server enforces both; the button just reflects them.

struct AdminTopActiveView: View {
    let analytics: AdminAnalyticsPayload
    var passcode = ""

    /// Honest ranges only: per-day hours aren't stored per user, so there is
    /// no "Today" — This Week / This Month / All Time are what the server tracks.
    enum Range: String, CaseIterable {
        case week = "This Week"
        case month = "This Month"
        case allTime = "All Time"
    }

    @State private var range: Range = .week
    @State private var thanking: AdminInsightUser?
    @State private var thankedNow: Set<String> = []

    private var ranked: [AdminInsightUser] {
        switch range {
        case .week: return analytics.topActive
        case .month: return analytics.topActive.sorted { $0.monthHours > $1.monthHours }
        case .allTime: return analytics.topActive.sorted { $0.totalHours > $1.totalHours }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if !ranked.isEmpty { podiumCard }
                if ranked.count > 3 { listCard }
                Text("Score (0–100) weights the present: recency, shifts and hours this week, and current streak. The heart sends a thank-you push: once per person every 90 days, and only to people who used the app in the last 7 days.")
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
        .navigationTitle("Top Active Users")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $thanking) { user in
            AdminThankYouSheet(user: user, passcode: passcode) {
                thankedNow.insert(user.uid)
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: 1. Summary

    private var summaryCard: some View {
        let users = analytics.topActive
        let power = users.filter { $0.score >= 70 }.count
        let weekHours = users.reduce(0) { $0 + $1.weeklyHours }
        let weekShifts = users.reduce(0) { $0 + $1.weeklyShifts }
        let thankable = users.filter { canThank($0) }.count
        return card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    eyebrow("Your most engaged")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(power)")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.Colors.text)
                        Text(power == 1 ? "power user" : "power users")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.subtext)
                    }
                    Text("Score 70+ out of the top \(users.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                }
                HStack(spacing: 10) {
                    stat(AppTheme.Format.hours(weekHours), "hours this week")
                    stat("\(weekShifts)", "shifts this week")
                    stat("\(thankable)", "ready to thank")
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.text)
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

    // MARK: 2. Top three

    private var podiumCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                eyebrow("Top 3 · \(range.rawValue)")
                ForEach(Array(ranked.prefix(3).enumerated()), id: \.element.id) { index, user in
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileAvatarView(name: user.displayName, size: 48, photoURL: user.photoURL, uid: user.uid)
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(medal(index)))
                                .overlay(Circle().stroke(AppTheme.Colors.card, lineWidth: 2))
                                .offset(x: 3, y: 3)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            nameLine(user, size: 16)
                            Text(detail(for: user))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.subtext)
                                .lineLimit(1)
                            Text(thanksLine(user))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.faint)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        scoreRing(user.score)
                        thankButton(user)
                    }
                    if index < min(ranked.count, 3) - 1 {
                        Divider().overlay(AppTheme.Colors.stroke)
                    }
                }
            }
        }
    }

    // MARK: 3. Everyone else

    private var listCard: some View {
        card {
            VStack(spacing: 0) {
                ForEach(Array(ranked.dropFirst(3).enumerated()), id: \.element.id) { offset, user in
                    HStack(spacing: 10) {
                        Text("\(offset + 4)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.Colors.faint)
                            .frame(width: 24, alignment: .leading)
                        ProfileAvatarView(name: user.displayName, size: 34, photoURL: user.photoURL, uid: user.uid)
                        VStack(alignment: .leading, spacing: 2) {
                            nameLine(user, size: 14)
                            Text(detail(for: user))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.subtext)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text("\(user.score)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(scoreTint(user.score))
                        thankButton(user)
                    }
                    .padding(.vertical, 8)
                    if offset < ranked.count - 4 {
                        Divider().overlay(AppTheme.Colors.stroke)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func nameLine(_ user: AdminInsightUser, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            Text(user.displayName)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .lineLimit(1)
            if user.verified { VerifiedBadgeView(variant: .static, size: 12) }
            if user.level > 0 {
                Text(user.prestige > 0 ? "L\(user.level)·P\(user.prestige)" : "L\(user.level)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.accent)
            }
        }
    }

    private func scoreRing(_ score: Int) -> some View {
        ZStack {
            Circle().stroke(AppTheme.Colors.stroke, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(scoreTint(score), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.text)
        }
        .frame(width: 38, height: 38)
        .accessibilityLabel("Score \(score)")
    }

    private func canThank(_ user: AdminInsightUser) -> Bool {
        user.canThank && !thankedNow.contains(user.uid)
    }

    private func thankButton(_ user: AdminInsightUser) -> some View {
        let ready = canThank(user)
        let sent = thankedNow.contains(user.uid) || user.thankBlockedReason == "cooldown"
        return Button {
            Haptics.lightTap()
            thanking = user
        } label: {
            Image(systemName: sent ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 34, height: 34)
                .foregroundStyle(ready ? AppTheme.Colors.accent : sent ? AppTheme.Colors.danger.opacity(0.7) : AppTheme.Colors.faint)
                .background(Circle().fill(AppTheme.Colors.card2))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityLabel(ready ? "Thank \(user.displayName)" : thanksLine(user))
    }

    private func thanksLine(_ user: AdminInsightUser) -> String {
        if thankedNow.contains(user.uid) { return "Thanked just now" }
        if let last = user.lastThanksAt, user.thankBlockedReason == "cooldown" {
            let next = user.nextThanksAt.map { " · next \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""
            return "Thanked \(last.formatted(.relative(presentation: .named)))\(next)"
        }
        if user.thankBlockedReason == "inactive" { return "Not active in the last 7 days" }
        return user.thanksCount > 0 ? "Ready to thank again" : "Never thanked"
    }

    private func detail(for user: AdminInsightUser) -> String {
        var parts: [String]
        switch range {
        case .week: parts = [AppTheme.Format.hours(user.weeklyHours), "\(user.weeklyShifts) shifts"]
        case .month: parts = [AppTheme.Format.hours(user.monthHours) + " this month"]
        case .allTime: parts = [AppTheme.Format.hours(user.totalHours) + " lifetime"]
        }
        if user.currentStreak > 0 { parts.append("\(user.currentStreak)d streak") }
        return parts.joined(separator: " • ")
    }

    private func scoreTint(_ score: Int) -> Color {
        if score >= 70 { return AppTheme.Colors.success }
        if score >= 35 { return AppTheme.Colors.accent }
        return AppTheme.Colors.faint
    }

    private func medal(_ index: Int) -> Color {
        switch index {
        case 0: return AppColors.gold
        case 1: return Color(white: 0.62)
        default: return Color(red: 0.72, green: 0.45, blue: 0.26)
        }
    }

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

// MARK: - Thank-you sheet

/// Preview and (optionally) edit the thank-you push, then send it.
struct AdminThankYouSheet: View {
    let user: AdminInsightUser
    let passcode: String
    let onSent: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var message = ""
    @State private var sending = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ProfileAvatarView(name: user.displayName, size: 40, photoURL: user.photoURL, uid: user.uid)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("\(AppTheme.Format.hours(user.totalHours)) lifetime · score \(user.score)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.subtext)
                        }
                    }
                }
                Section {
                    TextField("Title", text: $title)
                    TextField("Message", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Push notification")
                } footer: {
                    Text("They can get one thank-you every 90 days.")
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(AppTheme.Colors.danger) }
                }
            }
            .navigationTitle("Say thanks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                                      || message.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear {
                guard title.isEmpty else { return }
                let name = user.displayName.trimmingCharacters(in: .whitespaces)
                title = name.isEmpty ? "Thank you for tracking with us" : "Thank you, \(name)"
                let hours = Int(user.totalHours.rounded())
                message = hours >= 1
                    ? "You've logged \(hours.formatted()) hours with Hour Tracker. Thanks for using the app as much as you do. It means a lot."
                    : "Thanks for using Hour Tracker as much as you do. It means a lot."
            }
        }
    }

    private func send() async {
        sending = true
        errorText = nil
        defer { sending = false }
        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("adminSendAppreciation")
                .call([
                    "passcode": passcode,
                    "uid": user.uid,
                    "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                    "body": message.trimmingCharacters(in: .whitespacesAndNewlines),
                ])
            Haptics.success()
            onSent()
            dismiss()
        } catch {
            errorText = error.localizedDescription
            Haptics.error()
        }
    }
}

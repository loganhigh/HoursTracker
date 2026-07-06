import SwiftUI
import Combine
import UIKit

// MARK: - Preference key for top safe area (side menu)

private struct SideMenuTopSafeAreaKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Environment key for side menu

struct SideMenuKey: EnvironmentKey {
    static let defaultValue = SideMenuController()
}

extension EnvironmentValues {
    var sideMenu: SideMenuController {
        get { self[SideMenuKey.self] }
        set { self[SideMenuKey.self] = newValue }
    }
}

class SideMenuController: ObservableObject {
    @Published var isOpen: Bool = false
    @Published var payCycleSheet: PayCycleMenuPresentation?
    @Published var reportingSheet: Bool = false
    @Published var insightsSheet: Bool = false
    @Published var profileSheet: Bool = false
    @Published var careerSheet: Bool = false
    @Published var payHistorySheet: Bool = false
    @Published var friendsSheet: Bool = false
    @Published var accountSheet: Bool = false
    @Published var premiumSheet: Bool = false
    @Published var achievementsSheet: Bool = false
    @Published var thisMonthSheet: Bool = false
    @Published var yearArchivesSheet: Bool = false
    @Published var globalLeaderboardSheet: Bool = false

    func open() { isOpen = true }
    func close() { isOpen = false }
    func toggle() { isOpen.toggle() }
}

/// Wraps a pay cycle opened from the side menu with its screen title and layout flags.
struct PayCycleMenuPresentation: Identifiable {
    let cycle: PayCycle
    let navigationTitle: String
    let showsWeekSummary: Bool

    var id: String { "\(navigationTitle)-\(cycle.start.timeIntervalSince1970)" }
}

// MARK: - Side menu container

struct SideMenuContainer<Content: View>: View {
    @StateObject private var menuController = SideMenuController()
    @GestureState private var dragX: CGFloat = 0

    @ObservedObject var store: HoursStore

    let content: Content
    let onContactSupport: () -> Void
    let onReportBug: () -> Void
    let onRateApp: () -> Void
    let onSettings: () -> Void

    private let menuWidth: CGFloat = 285

    init(
        store: HoursStore,
        onContactSupport: @escaping () -> Void,
        onReportBug: @escaping () -> Void,
        onRateApp: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self.onContactSupport = onContactSupport
        self.onReportBug = onReportBug
        self.onRateApp = onRateApp
        self.onSettings = onSettings
        self.content = content()
    }

    private var currentMonthStart: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            content
                .environment(\.sideMenu, menuController)
                .offset(x: mainOffset)
                .overlay {
                    if menuController.isOpen {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture { menuController.close() }
                            .transition(.opacity)
                    }
                }

            SideMenuView(
                store: store,
                menuController: menuController,
                onClose: { menuController.close() },
                onContactSupport: { menuController.close(); onContactSupport() },
                onReportBug: { menuController.close(); onReportBug() },
                onRateApp: { menuController.close(); onRateApp() },
                onSettings: { menuController.close(); onSettings() }
            )
            .frame(width: menuWidth)
            .offset(x: menuOffset)
            .shadow(color: Color.black.opacity(0.28), radius: 20, x: 6, y: 0)
        }
        .animation(AppMotion.Spring.smooth, value: menuController.isOpen)
        .gesture(dragGesture)
        .sheet(item: $menuController.payCycleSheet) { presentation in
            PayCycleMenuSheetHost(store: store, presentation: presentation)
        }
        .sheet(isPresented: $menuController.reportingSheet) {
            ReportingView(store: store)
        }
        .sheet(isPresented: $menuController.insightsSheet) {
            InsightsMenuSheetHost(store: store)
        }
        .sheet(isPresented: $menuController.profileSheet) {
            ProfileView(store: store)
        }
        .sheet(isPresented: $menuController.careerSheet) {
            NavigationStack {
                CareerView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { menuController.careerSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $menuController.payHistorySheet) {
            NavigationStack {
                PayHistoryView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { menuController.payHistorySheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $menuController.friendsSheet) {
            FriendsView(store: store)
                .environmentObject(AuthService.shared)
        }
        .sheet(isPresented: $menuController.premiumSheet) {
            PremiumUpgradeView()
        }
        .sheet(isPresented: $menuController.accountSheet) {
            AccountView(store: store)
                .environmentObject(AuthService.shared)
        }
        .sheet(isPresented: $menuController.achievementsSheet) {
            AchievementsView(store: store)
                .environmentObject(AuthService.shared)
        }
        .sheet(isPresented: $menuController.thisMonthSheet) {
            NavigationStack {
                MonthDetailView(store: store, monthDate: currentMonthStart)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { menuController.thisMonthSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $menuController.yearArchivesSheet) {
            YearArchivesListView(store: store)
        }
        .sheet(isPresented: $menuController.globalLeaderboardSheet) {
            GlobalLeaderboardView()
                .environmentObject(AuthService.shared)
        }
    }

    private var mainOffset: CGFloat {
        let base = menuController.isOpen ? menuWidth : 0
        let proposed = base + dragX
        return min(menuWidth, max(0, proposed))
    }

    private var menuOffset: CGFloat {
        let base = menuController.isOpen ? 0 : -menuWidth
        let proposed = base + dragX
        return min(0, max(-menuWidth, proposed))
    }

    /// Swipe-to-open only engages when the drag starts within this many points
    /// of the left edge, matching the standard iOS edge-swipe pattern so it
    /// doesn't compete with horizontal scrolling/carousels elsewhere on screen.
    private let openEdgeWidth: CGFloat = 28

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($dragX) { value, state, _ in
                let x = value.translation.width
                let y = value.translation.height
                guard abs(x) > abs(y) else { return }
                if menuController.isOpen {
                    state = x
                } else if x > 0, value.startLocation.x <= openEdgeWidth {
                    // Left-edge swipe while closed live-drags the menu open.
                    state = x
                }
            }
            .onEnded { value in
                let x = value.translation.width
                if menuController.isOpen {
                    if x < -60 {
                        menuController.close()
                    }
                } else if x > 60, value.startLocation.x <= openEdgeWidth {
                    menuController.open()
                }
            }
    }
}

// MARK: - Sheet hosts (menu sits outside main NavigationStack)

private struct PayCycleMenuSheetHost: View {
    @ObservedObject var store: HoursStore
    let presentation: PayCycleMenuPresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PayCycleDetailView(
                store: store,
                initialCycle: presentation.cycle,
                navigationTitle: presentation.navigationTitle,
                showsWeekSummary: presentation.showsWeekSummary
            )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct InsightsMenuSheetHost: View {
    @ObservedObject var store: HoursStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InsightsView(store: store)
                .navigationTitle("Insights")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Year archives

private struct YearArchivesListView: View {
    @ObservedObject var store: HoursStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.yearArchives.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(AppTheme.Colors.faint)
                        Text("No archived years yet")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.text)
                        Text("Completed years appear here when entries roll over.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.subtext)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else {
                    List {
                        ForEach(store.yearArchives.sorted(by: { $0.year > $1.year })) { arch in
                            NavigationLink {
                                ArchivedYearEntriesView(store: store, archive: arch)
                            } label: {
                                Text("\(arch.year) — \(arch.entries.count) entries")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Year archives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ArchivedYearEntriesView: View {
    @ObservedObject var store: HoursStore
    let archive: YearArchive

    @State private var didCopyAll = false
    @State private var copyAllBurst = 0

    private var sortedEntries: [WorkEntry] {
        archive.entries.sorted { $0.date > $1.date }
    }

    private var workEntries: [WorkEntry] {
        sortedEntries.filter { !$0.isOffDay }
    }

    private var totalHours: Double {
        workEntries.reduce(0) { $0 + $1.paidHours }
    }

    private var regularHours: Double {
        workEntries.reduce(0) { $0 + store.payBreakdown(for: $1).regularHours }
    }

    private var overtimeHours: Double {
        workEntries.reduce(0) { $0 + store.payBreakdown(for: $1).overtimeHours }
    }

    private var offDayCount: Int {
        sortedEntries.filter(\.isOffDay).count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Total hours")
                            .font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text(AppTheme.Format.hours(totalHours, suffix: ""))
                            .font(AppDesignSystem.Typography.heroNumerals(size: 24, weight: .medium))
                    }

                    Divider()

                    HStack {
                        Text("Regular")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(AppTheme.Format.hours(regularHours))
                            .font(.system(size: 19, weight: .semibold, design: .monospaced))

                        Text("|")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)

                        Text("Overtime")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(AppTheme.Format.hours(overtimeHours))
                            .font(.system(size: 19, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }

                    Text("OFF DAYS - \(offDayCount)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.danger)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
            }

            Section {
                ForEach(sortedEntries) { entry in
                    NavigationLink {
                        EntryEditorView(store: store, mode: .edit(entry))
                    } label: {
                        EntryRowView(
                            entry: entry,
                            breakdown: store.payBreakdown(for: entry),
                            currencyCode: store.paySettings.currencyCode,
                            showPay: store.paySettings.showPayCalculations,
                            paySettings: store.paySettings
                        )
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = formatEntryForCopy(entry)
                            Haptics.lightTap()
                        } label: {
                            Label("Copy Entry", systemImage: "doc.on.doc")
                        }
                    }
                }

                Button {
                    copyAllEntries(sortedEntries)
                } label: {
                    HStack(spacing: 6) {
                        Spacer()
                        Image(systemName: didCopyAll ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 14, weight: .bold))
                        Text(didCopyAll ? "Copied!" : "Copy All")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(didCopyAll ? Color.green : AppTheme.Colors.accent)
                    .padding(.vertical, 8)
                    .contentTransition(.opacity)
                }
                .tapBurst(trigger: copyAllBurst, cornerRadius: 12, color: didCopyAll ? .green : AppTheme.Colors.accent)
            } header: {
                Text("Entries")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle(String(archive.year))
    }

    private func copyAllEntries(_ entries: [WorkEntry]) {
        UIPasteboard.general.string = copyAllText(for: entries)
        Haptics.success()
        copyAllBurst &+= 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            didCopyAll = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                didCopyAll = false
            }
        }
    }

    private func formatEntryForCopy(_ entry: WorkEntry) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        return entry.formattedForCopy(dateFormatter: df, timeFormatter: tf)
    }

    private func copyAllText(for entries: [WorkEntry]) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        return entries
            .sorted { $0.date > $1.date }
            .map { $0.formattedForCopy(dateFormatter: df, timeFormatter: tf) }
            .joined(separator: "\n\n")
    }
}

// MARK: - Side menu UI

private struct SideMenuView: View {
    @ObservedObject var store: HoursStore
    @ObservedObject var menuController: SideMenuController
    let onClose: () -> Void
    let onContactSupport: () -> Void
    let onReportBug: () -> Void
    let onRateApp: () -> Void
    let onSettings: () -> Void

    @AppStorage("profile_display_name") private var displayName: String = ""
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var topTrackers = TopTrackersService.shared
    @State private var topSafeArea: CGFloat = 0
    @Environment(\.openURL) private var openURL

    init(
        store: HoursStore,
        menuController: SideMenuController,
        onClose: @escaping () -> Void,
        onContactSupport: @escaping () -> Void,
        onReportBug: @escaping () -> Void,
        onRateApp: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.store = store
        self.menuController = menuController
        self.onClose = onClose
        self.onContactSupport = onContactSupport
        self.onReportBug = onReportBug
        self.onRateApp = onRateApp
        self.onSettings = onSettings
    }

    private var profileHeaderText: String {
        guard !displayName.isEmpty else { return "Your name" }
        return displayName
    }

    private var memberSinceText: String {
        if DeveloperConfig.isCEO(uid: authService.user?.uid) {
            return "CEO of Hour Tracker"
        }
        guard let first = store.entries.map(\.date).min() else {
            return "Member since —"
        }
        let y = Calendar.current.component(.year, from: first)
        return "Member since \(y)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Button {
                        menuController.close()
                        menuController.accountSheet = true
                    } label: {
                        HStack(spacing: 14) {
                            ProfileAvatarView(
                                name: profileHeaderText,
                                size: 56,
                                uid: authService.user?.uid,
                                showsAccentRing: true
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profileHeaderText)
                                    .font(AppDesignSystem.Typography.heroNumerals(size: 20, weight: .medium))
                                    .foregroundStyle(AppTheme.Colors.text)
                                    .lineLimit(1)
                                Text(memberSinceText)
                                    .font(AppDesignSystem.Typography.footnote)
                                    .foregroundStyle(AppTheme.Colors.faint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.Colors.faint)
                        }
                    }
                    .buttonStyle(InteractiveButtonStyle())

                    drawerSection(title: "Time") {
                        drawerRow(icon: "banknote", title: "This cheque") {
                            menuController.close()
                            menuController.payCycleSheet = PayCycleMenuPresentation(
                                cycle: store.currentPayCycle(),
                                navigationTitle: "This Cheque",
                                showsWeekSummary: true
                            )
                        }
                        drawerRow(icon: "banknote.fill", title: "Last cheque") {
                            menuController.close()
                            let current = store.currentPayCycle()
                            menuController.payCycleSheet = PayCycleMenuPresentation(
                                cycle: PayCycleEngine.previousCycle(
                                    before: current,
                                    settings: store.paySettings
                                ),
                                navigationTitle: "Last cheque",
                                showsWeekSummary: false
                            )
                        }
                        drawerRow(icon: "calendar", title: "This month") {
                            menuController.close()
                            menuController.thisMonthSheet = true
                        }
                        drawerRow(icon: "archivebox", title: "Year archives") {
                            menuController.close()
                            menuController.yearArchivesSheet = true
                        }
                    }

                    drawerSection(title: "App") {
                        drawerRow(icon: "gearshape", title: "Settings", titleWeight: .bold) {
                            onSettings()
                        }
                        drawerRow(icon: "globe", title: "Website") {
                            menuController.close()
                            openURL(AppLegalURLs.website)
                        }
                        drawerRow(icon: "envelope", title: "Contact") {
                            menuController.close()
                            openURL(AppLegalURLs.support)
                        }
                    }

                    topTrackersSection
                }
                .padding(.horizontal, 22)
                .padding(.top, max(topSafeArea, 8) + 6)
                .padding(.bottom, 24)
            }

        }
        .onAppear { topTrackers.startListening() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SideMenuTopSafeAreaKey.self, value: geo.safeAreaInsets.top)
            }
        )
        .onPreferenceChange(SideMenuTopSafeAreaKey.self) { topSafeArea = $0 }
        .background(AppTheme.Colors.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private var topTrackersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP 5 HOUR TRACKERS")
                .font(AppDesignSystem.Typography.sectionLabel)
                .tracking(1)
                .foregroundStyle(AppTheme.Colors.faint)

            VStack(spacing: 0) {
                if topTrackers.topTrackers.isEmpty {
                    HStack {
                        Text(topTrackers.hasLoaded ? "No rankings yet" : "Loading…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.Colors.faint)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                } else {
                    ForEach(topTrackers.topTrackers.prefix(5)) { tracker in
                        topTrackerRow(tracker: tracker)
                        if tracker.id != topTrackers.topTrackers.prefix(5).last?.id {
                            Divider()
                                .overlay(AppTheme.Colors.stroke)
                                .padding(.leading, 52)
                        }
                    }

                    Button {
                        menuController.close()
                        menuController.globalLeaderboardSheet = true
                    } label: {
                        Text("See more")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.Colors.accent.opacity(0.1))
                            )
                    }
                    .buttonStyle(InteractiveButtonStyle())
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .padding(.top, 4)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
            )
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.98, green: 0.79, blue: 0.28) // gold
        case 2: return Color(red: 0.75, green: 0.79, blue: 0.85) // silver
        case 3: return Color(red: 0.83, green: 0.55, blue: 0.35) // bronze
        default: return AppTheme.Colors.accent
        }
    }

    private func topTrackerRow(tracker: TopTracker) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rankColor(tracker.rank).opacity(tracker.rank <= 3 ? 0.22 : 0.12))
                    .frame(width: 28, height: 28)
                Text("\(tracker.rank)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(rankColor(tracker.rank))
            }

            HStack(spacing: 5) {
                Text(tracker.name)
                    .font(.system(size: 15, weight: tracker.rank <= 3 ? .semibold : .medium))
                    .foregroundStyle(AppTheme.Colors.text)
                    .lineLimit(1)
                if let flag = CountryFlag.emoji(
                    for: CountryFlag.leaderboardCode(
                        trackerUid: tracker.uid,
                        serverCode: tracker.countryCode,
                        currentUid: authService.user?.uid
                    )
                ) {
                    Text(flag)
                        .font(.system(size: 15))
                }
            }

            Spacer()

            Text(hoursLabel(tracker.hours))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.subtext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func hoursLabel(_ hours: Double) -> String {
        if hours >= 1000 {
            return String(format: "%.0fh", hours)
        }
        return String(format: "%.1fh", hours)
    }

    private func drawerSection(title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppDesignSystem.Typography.sectionLabel)
                .tracking(1)
                .foregroundStyle(AppTheme.Colors.faint)
            VStack(spacing: 0) {
                rows()
            }
            .background(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                    .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
            )
        }
    }

    private func drawerRow(
        icon: String,
        title: String,
        titleWeight: Font.Weight = .medium,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .frame(width: 26, alignment: .center)
                Text(title)
                    .font(.system(size: 15, weight: titleWeight))
                    .foregroundStyle(AppTheme.Colors.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractiveButtonStyle())
    }

    private func menuItemWithImage(imageName: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.faint)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(InteractiveButtonStyle())
    }

    private func openSupportPage() {
        openURL(AppLegalURLs.support)
    }

    private func openWebsite() {
        openURL(AppLegalURLs.website)
    }
}

// MARK: - Pay Period Mini Calendar

/// Pay-period breakdown as a horizontal bar chart — one row per day from the
/// start of the cheque through today, with a proportional bar for hours worked.
/// Unworked past days show a faded track and an em dash.
struct PayPeriodMiniCalendar: View {
    let cycle: PayCycle
    let entries: [WorkEntry]

    @Environment(\.semanticColors) private var theme

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    /// Total paid hours logged on each day in the cycle (non-off-day entries).
    private var hoursByDay: [Date: Double] {
        var totals: [Date: Double] = [:]
        for entry in entries where !entry.isOffDay {
            let day = cal.startOfDay(for: entry.date)
            totals[day, default: 0] += entry.paidHours
        }
        return totals
    }

    /// Count of shifts logged on each day (non-off-day entries).
    private var shiftsByDay: [Date: Int] {
        var counts: [Date: Int] = [:]
        for entry in entries where !entry.isOffDay {
            let day = cal.startOfDay(for: entry.date)
            counts[day, default: 0] += 1
        }
        return counts
    }

    /// Days explicitly logged as an off day.
    private var offDays: Set<Date> {
        Set(entries.filter(\.isOffDay).map { cal.startOfDay(for: $0.date) })
    }

    /// First off-day entry per calendar day (for reason / holiday label).
    private var offDayEntryByDay: [Date: WorkEntry] {
        var map: [Date: WorkEntry] = [:]
        for entry in entries.filter(\.isOffDay) {
            let day = cal.startOfDay(for: entry.date)
            map[day] = entry
        }
        return map
    }

    private func isHolidayDay(_ day: Date) -> Bool {
        guard let entry = offDayEntryByDay[day] else { return false }
        if entry.isHoliday { return true }
        return entry.offDayReason.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare("Holiday", options: .caseInsensitive) == .orderedSame
    }

    private func offDayBarLabel(for day: Date) -> String {
        isHolidayDay(day) ? "Holiday" : "OFF"
    }

    /// Days from the start of the cheque through today (never into the future).
    /// Falls back to the whole period if today lands outside the cycle.
    private var days: [Date] {
        let start = cal.startOfDay(for: cycle.start)
        let lastCycleDay = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: cycle.end)) ?? cycle.end
        let cap = min(lastCycleDay, today)
        var list: [Date] = []
        var day = start
        while day <= (cap >= start ? cap : lastCycleDay) {
            list.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return list
    }

    private var totalHours: Double {
        hoursByDay.values.reduce(0, +)
    }

    private var totalShifts: Int {
        shiftsByDay.values.reduce(0, +)
    }

    private var rangeLabel: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        let lastDay = cal.date(byAdding: .day, value: -1, to: cycle.end) ?? cycle.end
        return "\(df.string(from: cycle.start)) – \(df.string(from: lastDay))"
    }

    private var summaryLabel: String {
        let shiftWord = totalShifts == 1 ? "shift" : "shifts"
        return "\(totalShifts) \(shiftWord) • \(hoursDisplay(totalHours))"
    }

    var body: some View {
        VStack(spacing: 10) {
            // Header — single centered stack so title, dates, and summary align
            VStack(spacing: 3) {
                Text("This Cheque")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(rangeLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(summaryLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Bars
            VStack(spacing: 3) {
                ForEach(days, id: \.self) { day in
                    dayRow(day)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func dayRow(_ day: Date) -> some View {
        let hours = hoursByDay[day] ?? 0
        let shifts = shiftsByDay[day] ?? 0
        let hasShift = hours > 0 || shifts > 0
        let isOffDay = offDays.contains(day)
        let isHoliday = isHolidayDay(day)

        HStack(spacing: 10) {
            // Day label
            VStack(alignment: .center, spacing: 0) {
                Text(dayAbbrev(day))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hasShift || isOffDay ? AppTheme.Colors.subtext : AppTheme.Colors.faint)
                Text(dayNum(day))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(hasShift || isOffDay ? AppTheme.Colors.text : AppTheme.Colors.faint)
            }
            .frame(width: 36)

            // Progress bar — flat full-width pill for every logged day (no
            // proportional fill) so the row reads calmly at a glance; hours
            // are still called out precisely in the trailing column.
            GeometryReader { geo in
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(offDayRowFill(hasShift: hasShift, isOffDay: isOffDay, isHoliday: isHoliday, theme: theme))
                        .frame(height: 24)
                    if hasShift {
                        Text("WORKED")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(AppTheme.Colors.success)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                            .frame(width: geo.size.width, height: 24, alignment: .center)
                    }
                    if isOffDay {
                        Text(offDayBarLabel(for: day))
                            .font(.system(size: isHoliday ? 10 : 11, weight: .heavy, design: .rounded))
                            .tracking(isHoliday ? 0.3 : 1)
                            .foregroundStyle(
                                isHoliday
                                    ? Color(red: 0.34, green: 0.74, blue: 0.46)
                                    : AppTheme.Colors.danger
                            )
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                            .frame(width: geo.size.width, height: 24, alignment: .center)
                    }
                }
            }
            .frame(height: 24)

            // Hours + shift count
            VStack(alignment: .trailing, spacing: 0) {
                Text(hasShift ? hoursDisplay(hours) : "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(hasShift ? AppTheme.Colors.text : AppTheme.Colors.faint)
                    .monospacedDigit()
                if shifts > 1 {
                    Text("\(shifts) shifts")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }
            .frame(width: 52, alignment: .trailing)
        }
        .opacity(hasShift || isOffDay ? 1 : 0.55)
    }

    /// Off days get a dark red pill (holidays get a dark green pill to match
    /// their green "Holiday" label) so they read as distinctly different
    /// from worked days at a glance, not just a neutral faded track.
    private func offDayRowFill(hasShift: Bool, isOffDay: Bool, isHoliday: Bool, theme: SemanticColors) -> Color {
        if hasShift { return AppTheme.Colors.success.opacity(0.18) }
        if isOffDay {
            return isHoliday
                ? Color(red: 0.34, green: 0.74, blue: 0.46).opacity(0.18)
                : AppTheme.Colors.danger.opacity(0.22)
        }
        return theme.accent.opacity(0.05)
    }

    private func dayAbbrev(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func dayNum(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private func hoursDisplay(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value) + "h"
        }
        return AppTheme.Format.hours(value)
    }
}


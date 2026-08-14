import SwiftUI
import FirebaseFunctions

/// A user row returned by the `adminListUsers` callable.
private struct AdminUser: Identifiable, Equatable {
    let uid: String
    let displayName: String
    var friendCode: String
    var email: String
    /// From the Auth profile — the provider's real name at first sign-in,
    /// untouched by the in-app display-name editor.
    var authName: String = ""
    var createdAt: Date?
    /// Last credential authentication. Rarely moves — Sign in with Apple
    /// persists — so it says almost nothing about whether someone still uses
    /// the app. `lastActiveAt` is the honest one.
    var lastSignInAt: Date?
    /// Last app foreground, from presence; falls back to an ID-token refresh.
    var lastActiveAt: Date?
    var lastActiveFromPresence: Bool = false
    var level: Int
    var prestige: Int
    let totalHours: Double
    var adminFloorLevel: Int?
    var adminFloorPrestige: Int?
    var adminEquippedTitle: String
    var equippedTitle: String
    var countryCode: String
    var hasReviewedApp: Bool = false
    var profilePending: Bool

    var id: String { uid }

    var hasFloor: Bool { (adminFloorLevel ?? 0) > 0 || (adminFloorPrestige ?? 0) > 0 }
    var hasAdminTitle: Bool { !adminEquippedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasCountryFlag: Bool { CountryFlag.emoji(for: countryCode) != nil }

    /// A code is only stamped on the user's first authenticated app launch, so
    /// accounts that signed up but never opened Friends legitimately have none.
    var friendCodeDisplay: String { friendCode.isEmpty ? "—" : friendCode }
}

/// Admin-only console: list every user and set a floor on their level /
/// prestige. Every action is re-verified server-side with the account UID
/// and passcode, so this screen is a convenience surface, not the security
/// boundary. Reachable from Settings when signed in as the CEO account.
struct AdminPanelView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var cloudSync: CloudSyncManager
    @Environment(\.dismiss) private var dismiss

    /// Kept only as inert plumbing to the callables' legacy parameter — the
    /// server now authorizes purely on the signed-in admin uid.
    private let passcode = ""
    @State private var isLoading = false
    @State private var users: [AdminUser] = []
    @State private var search = ""
    @State private var errorMessage: String?
    @State private var editing: AdminUser?
    @State private var isBulkRefreshing = false
    @State private var isClearingFloors = false
    @State private var isRefreshingLeaderboard = false
    @State private var bulkRefreshMessage: String?
    @State private var liveProgressText: String?
    @State private var listSummary: String?
    @State private var progressPollTask: Task<Void, Never>?

    private let functions = Functions.functions(region: "us-central1")

    private var isAdmin: Bool {
        DeveloperConfig.isCEO(uid: authService.user?.uid)
    }

    private var footerText: String {
        if isBulkRefreshing, let liveProgressText { return liveProgressText }
        return bulkRefreshMessage ?? "Recomputes every user's stats now, including anyone who hasn't shown up yet because they haven't logged a shift since this feature launched. Can take up to a couple minutes for larger user bases — feel free to leave this screen open and wait. If levels look wrong, tap Repair all levels first — it clears accidental admin floors and recomputes everyone from XP."
    }

    private var footerColor: Color {
        if isBulkRefreshing { return AppTheme.Colors.subtext }
        return bulkRefreshMessage != nil ? AppTheme.Colors.success : AppTheme.Colors.faint
    }

    private var filteredUsers: [AdminUser] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return users }
        // Friend codes get written down and read back with separators ("TH-4829",
        // "th 4829"), so match them against a stripped form of the query.
        let codeQuery = q.filter { $0.isLetter || $0.isNumber }
        return users.filter { user in
            user.displayName.lowercased().contains(q)
                || user.uid.lowercased().contains(q)
                || user.email.lowercased().contains(q)
                || (!codeQuery.isEmpty && user.friendCode.lowercased().contains(codeQuery))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isAdmin {
                    notAuthorized
                } else {
                    userList
                }
            }
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            // Loads immediately — the Unlock tap that used to trigger this
            // went with the passcode gate.
            .task {
                if isAdmin, users.isEmpty { await loadUsers() }
            }
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if isAdmin {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            Task { await loadUsers() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .sheet(item: $editing) { user in
                AdminEditUserSheet(
                    user: user,
                    passcode: passcode,
                    currentUid: authService.user?.uid,
                    cloudSync: cloudSync
                ) { updated in
                    if let idx = users.firstIndex(where: { $0.uid == updated.uid }) {
                        users[idx] = updated
                    }
                }
            }
        }
    }

    // MARK: - States

    private var notAuthorized: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.slash")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(AppTheme.Colors.faint)
            Text("Not authorized")
                .font(.headline)
                .foregroundStyle(AppTheme.Colors.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var userList: some View {
        VStack(spacing: 0) {
            if isLoading && users.isEmpty {
                // Full-frame labelled loading state: with the passcode gate
                // gone this is the console's opening frame, and the old bare
                // spinner between two Spacers read as a broken empty sheet
                // while adminListUsers walked every auth account.
                SoftLoadingIndicator(title: "Loading users…")
            } else {
                List {
                    Section {
                        NavigationLink {
                            AdminVerifiedInboxView(passcode: passcode) { approvedUid in
                                if let idx = users.firstIndex(where: { $0.uid == approvedUid }) {
                                    users[idx].hasReviewedApp = true
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                VerifiedBadgeView(variant: .static, size: 16)
                                Text("Verified inbox")
                            }
                        }
                        .listRowBackground(AppTheme.Colors.card)

                        NavigationLink {
                            AdminAnnouncementView(passcode: passcode)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "megaphone.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AppTheme.Colors.accent)
                                Text("Announcement")
                            }
                        }
                        .listRowBackground(AppTheme.Colors.card)
                    }

                    Section {
                        Button {
                            Task { await bulkRefreshAllUsers() }
                        } label: {
                            HStack {
                                if isBulkRefreshing { ProgressView() }
                                Text(isBulkRefreshing ? "Refreshing all users…" : "Refresh all users")
                            }
                        }
                        .disabled(isBulkRefreshing || isRefreshingLeaderboard)
                        .listRowBackground(AppTheme.Colors.card)

                        Button {
                            Task { await refreshLeaderboard() }
                        } label: {
                            HStack {
                                if isRefreshingLeaderboard { ProgressView() }
                                Text(isRefreshingLeaderboard ? "Refreshing leaderboard…" : "Refresh global leaderboard")
                            }
                        }
                        .disabled(isBulkRefreshing || isRefreshingLeaderboard)
                        .listRowBackground(AppTheme.Colors.card)

                        Button(role: .destructive) {
                            Task { await clearAllFloors() }
                        } label: {
                            HStack {
                                if isClearingFloors { ProgressView() }
                                Text(isClearingFloors ? "Repairing levels…" : "Repair all levels")
                            }
                        }
                        .disabled(isBulkRefreshing || isClearingFloors || isRefreshingLeaderboard)
                        .listRowBackground(AppTheme.Colors.card)
                    } footer: {
                        Text(footerText)
                            .foregroundStyle(footerColor)
                    }

                    Section {
                        ForEach(filteredUsers) { user in
                            Button { editing = user } label: {
                                adminUserRow(user)
                            }
                            .listRowBackground(AppTheme.Colors.card)
                        }
                    } header: {
                        Text(listSummary ?? "\(users.count) users • sorted by lifetime hours")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.faint)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .searchable(text: $search, prompt: "Search name, friend code, email, or UID")
                .refreshable { await loadUsers() }
            }
        }
    }

    private func adminUserRow(_ user: AdminUser) -> some View {
        HStack(spacing: 12) {
            ProfileAvatarView(name: user.displayName.isEmpty ? "?" : user.displayName, size: 40, uid: user.uid)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(user.displayName.isEmpty ? "(no name)" : user.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.text)
                        .lineLimit(1)
                    if user.hasReviewedApp {
                        VerifiedBadgeView(variant: .static, size: 13)
                    }
                    if let flag = CountryFlag.emoji(for: user.countryCode) {
                        Text(flag)
                            .font(.system(size: 14))
                    }
                }
                HStack(spacing: 6) {
                    Text("Lv \(user.level)")
                    Text("•")
                    Text("Prestige \(user.prestige)")
                    Text("•")
                    Text(String(format: "%.0fh", user.totalHours))
                    if !user.friendCode.isEmpty {
                        Text("•")
                        Text(user.friendCode)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
                .lineLimit(1)
                if !user.equippedTitle.isEmpty {
                    Text(user.equippedTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(user.hasAdminTitle ? AppTheme.Colors.accent : AppTheme.Colors.faint)
                        .lineLimit(1)
                }
            }
            Spacer()
            if user.hasFloor || user.hasAdminTitle {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
            } else if user.profilePending {
                Text("needs sync")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.warning)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.faint)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Networking

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await functions.httpsCallable("adminListUsers").call(["passcode": passcode])
            guard let data = result.data as? [String: Any],
                  let rawUsers = data["users"] as? [[String: Any]] else {
                errorMessage = "Unexpected response."
                return
            }
            users = rawUsers.map { AdminUser.parse($0) }
            if let authCount = data["authCount"] as? Int ?? (data["authCount"] as? NSNumber)?.intValue,
               let publicCount = data["publicProfileCount"] as? Int ?? (data["publicProfileCount"] as? NSNumber)?.intValue {
                listSummary = "\(users.count) listed • \(authCount) signed in • \(publicCount) synced profiles"
            } else {
                listSummary = "\(users.count) users • sorted by lifetime hours"
            }
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    private func bulkRefreshAllUsers() async {
        isBulkRefreshing = true
        bulkRefreshMessage = nil
        liveProgressText = "Starting…"
        startProgressPolling()
        defer {
            isBulkRefreshing = false
            progressPollTask?.cancel()
            progressPollTask = nil
        }
        do {
            // The server budget for this is 5 minutes (recomputing every user's
            // stats is real work), so the client needs to wait at least that
            // long too — the SDK's ~70s default would otherwise give up and
            // report failure while the server call is still legitimately running.
            let callable = functions.httpsCallable("adminRefreshAllUsers")
            callable.timeoutInterval = 280
            let result = try await callable.call(["passcode": passcode])
            let data = result.data as? [String: Any]
            let succeeded = (data?["succeeded"] as? Int) ?? (data?["succeeded"] as? NSNumber)?.intValue ?? 0
            let total = (data?["total"] as? Int) ?? (data?["total"] as? NSNumber)?.intValue ?? 0
            let authCount = (data?["authCount"] as? Int) ?? (data?["authCount"] as? NSNumber)?.intValue
            if let authCount {
                bulkRefreshMessage = "Refreshed \(succeeded)/\(total) profiles (\(authCount) auth accounts)."
            } else {
                bulkRefreshMessage = "Refreshed \(succeeded)/\(total) users."
            }
            await loadUsers()
        } catch {
            bulkRefreshMessage = nil
            errorMessage = friendlyError(error)
        }
    }

    private func clearAllFloors() async {
        isClearingFloors = true
        bulkRefreshMessage = nil
        liveProgressText = "Clearing floors…"
        startProgressPolling()
        defer {
            isClearingFloors = false
            progressPollTask?.cancel()
            progressPollTask = nil
        }
        do {
            let callable = functions.httpsCallable("adminClearAllFloors")
            callable.timeoutInterval = 280
            let result = try await callable.call(["passcode": passcode])
            let data = result.data as? [String: Any]
            let cleared = (data?["cleared"] as? Int) ?? (data?["cleared"] as? NSNumber)?.intValue ?? 0
            let succeeded = (data?["succeeded"] as? Int) ?? (data?["succeeded"] as? NSNumber)?.intValue ?? 0
            let total = (data?["total"] as? Int) ?? (data?["total"] as? NSNumber)?.intValue ?? 0
            bulkRefreshMessage = "Repaired levels for \(cleared) users with bad floors, then recomputed \(succeeded)/\(total) profiles."
            await loadUsers()
        } catch {
            bulkRefreshMessage = nil
            errorMessage = friendlyError(error)
        }
    }

    private func refreshLeaderboard() async {
        isRefreshingLeaderboard = true
        bulkRefreshMessage = nil
        defer { isRefreshingLeaderboard = false }
        do {
            let result = try await functions.httpsCallable("adminRefreshLeaderboard").call(["passcode": passcode])
            let data = result.data as? [String: Any]
            let total = (data?["totalRanked"] as? Int) ?? (data?["totalRanked"] as? NSNumber)?.intValue ?? 0
            bulkRefreshMessage = "Global leaderboard refreshed (\(total) ranked)."
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Polls `adminRefreshProgress` (an Admin-SDK read behind the same
    /// UID+passcode gate as every other admin callable) so the panel shows
    /// live counts while `adminRefreshAllUsers` works through each chunk,
    /// instead of an indefinite spinner with no way to tell whether it's
    /// still alive or has actually stalled.
    private func startProgressPolling() {
        progressPollTask?.cancel()
        progressPollTask = Task {
            while !Task.isCancelled {
                do {
                    let result = try await functions.httpsCallable("adminRefreshProgress").call(["passcode": passcode])
                    let data = result.data as? [String: Any]
                    if data?["exists"] as? Bool == true {
                        let processed = (data?["processed"] as? Int) ?? (data?["processed"] as? NSNumber)?.intValue ?? 0
                        let total = (data?["total"] as? Int) ?? (data?["total"] as? NSNumber)?.intValue ?? 0
                        let failed = (data?["failed"] as? Int) ?? (data?["failed"] as? NSNumber)?.intValue ?? 0
                        if let error = data?["error"] as? String {
                            liveProgressText = "Server error: \(error)"
                        } else if total > 0 {
                            let failedSuffix = failed > 0 ? " (\(failed) failed)" : ""
                            liveProgressText = "\(processed)/\(total) users processed\(failedSuffix)…"
                        } else {
                            liveProgressText = "Fetching user list…"
                        }
                    }
                } catch {
                    // Transient poll failures shouldn't blank out the last known
                    // progress — just leave it as-is and try again next tick.
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: ns.code) {
            switch code {
            case .permissionDenied: return "This account isn't the admin."
            case .unauthenticated: return "Sign in required."
            default: break
            }
        }
        return error.localizedDescription
    }
}

private extension AdminUser {
    static func parse(_ dict: [String: Any]) -> AdminUser {
        func int(_ key: String) -> Int? {
            if let v = dict[key] as? Int { return v }
            if let v = dict[key] as? Int64 { return Int(v) }
            if let v = dict[key] as? NSNumber { return v.intValue }
            return nil
        }
        func double(_ key: String) -> Double {
            if let v = dict[key] as? Double { return v }
            if let v = dict[key] as? Int { return Double(v) }
            if let v = dict[key] as? NSNumber { return v.doubleValue }
            return 0
        }
        // Epoch millis from the callable; absent/null for accounts Auth has no
        // metadata for, which renders as "—" rather than a bogus 1970 date.
        func date(_ key: String) -> Date? {
            guard let ms = dict[key] as? NSNumber, ms.doubleValue > 0 else { return nil }
            return Date(timeIntervalSince1970: ms.doubleValue / 1000)
        }
        return AdminUser(
            uid: dict["uid"] as? String ?? "",
            displayName: dict["displayName"] as? String ?? "",
            friendCode: (dict["friendCode"] as? String ?? "").uppercased(),
            email: dict["email"] as? String ?? "",
            authName: dict["authName"] as? String ?? "",
            createdAt: date("createdAt"),
            lastSignInAt: date("lastSignInAt"),
            lastActiveAt: date("lastActiveAt"),
            lastActiveFromPresence: dict["lastActiveFromPresence"] as? Bool ?? false,
            level: int("level") ?? 1,
            prestige: int("prestige") ?? 0,
            totalHours: double("totalHours"),
            adminFloorLevel: int("adminFloorLevel"),
            adminFloorPrestige: int("adminFloorPrestige"),
            adminEquippedTitle: dict["adminEquippedTitle"] as? String ?? "",
            equippedTitle: dict["equippedTitle"] as? String ?? "",
            countryCode: (dict["countryCode"] as? String ?? "").uppercased(),
            hasReviewedApp: dict["hasReviewedApp"] as? Bool ?? false,
            profilePending: dict["profilePending"] as? Bool ?? false
        )
    }
}

// MARK: - Edit sheet

private struct AdminEditUserSheet: View {
    let user: AdminUser
    let passcode: String
    let currentUid: String?
    let cloudSync: CloudSyncManager
    let onSaved: (AdminUser) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var levelText: String
    @State private var prestigeText: String
    @State private var titleText: String
    @State private var countryCode: String
    // Tracks whether the user actually typed into the field this session —
    // distinct from the text merely differing from `user.level`/`user.prestige`.
    // A raw text comparison can't tell "retyped the same target level on
    // purpose (e.g. to re-apply after it didn't stick)" apart from "field left
    // untouched", which previously made Save silently do nothing when the
    // number happened to match whatever was last cached in the admin list.
    @State private var levelEdited = false
    @State private var prestigeEdited = false
    @State private var isSaving = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var refreshedMessage: String?
    @State private var copiedField: String?
    @State private var verifiedDraft: Bool
    @State private var isSavingVerified = false

    private let functions = Functions.functions(region: "us-central1")

    init(
        user: AdminUser,
        passcode: String,
        currentUid: String?,
        cloudSync: CloudSyncManager,
        onSaved: @escaping (AdminUser) -> Void
    ) {
        self.user = user
        self.passcode = passcode
        self.currentUid = currentUid
        self.cloudSync = cloudSync
        self.onSaved = onSaved
        _levelText = State(initialValue: "\(user.level)")
        _prestigeText = State(initialValue: "\(user.prestige)")
        _titleText = State(initialValue: user.adminEquippedTitle)
        _countryCode = State(initialValue: user.countryCode)
        _verifiedDraft = State(initialValue: user.hasReviewedApp)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Current level")
                        Spacer()
                        Text("\(user.level)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Current prestige")
                        Spacer()
                        Text("\(user.prestige)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Lifetime hours")
                        Spacer()
                        Text(String(format: "%.1f", user.totalHours)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Displayed title")
                        Spacer()
                        Text(user.equippedTitle.isEmpty ? "—" : user.equippedTitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    if user.adminFloorPrestige != nil {
                        HStack {
                            Text("Legacy prestige floor")
                            Spacer()
                            Text("P\(user.adminFloorPrestige ?? 0)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(user.displayName.isEmpty ? user.uid : user.displayName)
                }

                Section {
                    copyRow("Friend code", user.friendCodeDisplay, copyable: !user.friendCode.isEmpty)
                    copyRow("Email", user.email.isEmpty ? "—" : user.email, copyable: !user.email.isEmpty)
                    copyRow("Real name", user.authName.isEmpty ? "—" : user.authName, copyable: !user.authName.isEmpty)
                    copyRow("UID", user.uid, copyable: !user.uid.isEmpty)
                    HStack {
                        Text("Signed up")
                        Spacer()
                        Text(Self.absoluteDate(user.createdAt))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Last active")
                        Spacer()
                        Text(Self.absoluteDate(user.lastActiveAt))
                            .foregroundStyle(.secondary)
                    }
                    // Redundant beside a real activity time; only useful as a
                    // stand-in when the account has neither presence nor a
                    // token refresh on record.
                    if user.lastActiveAt == nil {
                        HStack {
                            Text("Last signed in")
                            Spacer()
                            Text(Self.absoluteDate(user.lastSignInAt))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text(accountFooterText)
                        .foregroundStyle(copiedField != nil ? AppTheme.Colors.success : AppTheme.Colors.faint)
                }

                Section {
                    Toggle(isOn: $verifiedDraft) {
                        HStack(spacing: 6) {
                            VerifiedBadgeView(variant: .static, size: 15)
                            Text("Verified mark")
                            if isSavingVerified {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isSavingVerified)
                    .onChange(of: verifiedDraft) { old, new in
                        guard old != new else { return }
                        Task { await setVerified(new) }
                    }
                } header: {
                    Text("Verified mark")
                } footer: {
                    Text("Grants or removes the checkmark beside their name everywhere other users see it. Applies immediately. Submissions with screenshots arrive in the Verified inbox on the main admin screen.")
                }

                Section {
                    TextField("Set level", text: $levelText)
                        .keyboardType(.numberPad)
                        .onChange(of: levelText) { levelEdited = true }
                    TextField("Set prestige", text: $prestigeText)
                        .keyboardType(.numberPad)
                        .onChange(of: prestigeText) { prestigeEdited = true }
                    Button("Reset to XP level", role: .destructive) {
                        Task { await save(resetToXP: true) }
                    }
                    .disabled(isSaving)
                } header: {
                    Text("Level & prestige")
                } footer: {
                    Text("Sets the user's current level and/or prestige. They keep earning XP and can level up or prestige normally after that. Only fields you actually edit are saved — leave a field untouched to skip it, even if you retype the same number it'll still be re-applied.")
                }

                Section {
                    TextField("Admin title override", text: $titleText)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Equipped title")
                } footer: {
                    Text("Overrides the badge title shown on their profile and to friends. Leave blank to remove the override and use their earned title.")
                }

                Section {
                    NavigationLink {
                        AdminCountryPickerView(selectedCode: $countryCode)
                    } label: {
                        HStack {
                            Text("Country flag")
                            Spacer()
                            if let flag = CountryFlag.emoji(for: countryCode) {
                                Text(flag)
                                    .font(.system(size: 20))
                            }
                            Text(adminCountryLabel(for: countryCode))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !countryCode.isEmpty {
                        Button("Clear country flag", role: .destructive) {
                            countryCode = ""
                        }
                    }
                } header: {
                    Text("Leaderboard flag")
                } footer: {
                    Text("Sets the flag shown beside their name on the global Top 5 board. They must have hours sharing enabled for it to appear publicly.")
                }

                Section {
                    Button {
                        Task { await forceRefresh() }
                    } label: {
                        HStack {
                            if isRefreshing { ProgressView() }
                            Text(isRefreshing ? "Refreshing…" : "Force refresh stats")
                        }
                    }
                    .disabled(isRefreshing || isSaving)
                } footer: {
                    Text("Recomputes this user's stats from their raw entries right now, without waiting for their next shift write. Useful if their friend-facing numbers look stale.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.danger)
                    }
                }

                if refreshedMessage != nil {
                    Section {
                        Text(refreshedMessage ?? "")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.success)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Edit user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    /// Applied on toggle rather than on Save: the mark is independent of the
    /// progression fields the Save button batches, and an immediate write
    /// matches how the inbox's Approve behaves.
    private func setVerified(_ verified: Bool) async {
        isSavingVerified = true
        errorMessage = nil
        defer { isSavingVerified = false }
        do {
            _ = try await functions.httpsCallable("adminSetVerified")
                .call(["passcode": passcode, "targetUid": user.uid, "verified": verified])
            Haptics.success()
            var updated = user
            updated.hasReviewedApp = verified
            onSaved(updated)
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
            verifiedDraft = !verified // roll the switch back; the write failed
        }
    }

    private func forceRefresh() async {
        isRefreshing = true
        errorMessage = nil
        refreshedMessage = nil
        defer { isRefreshing = false }
        do {
            _ = try await functions.httpsCallable("adminRecomputeUserStats")
                .call(["passcode": passcode, "targetUid": user.uid])
            refreshedMessage = "Stats refreshed."
        } catch {
            let ns = error as NSError
            if ns.domain == FunctionsErrorDomain,
               ns.code == FunctionsErrorCode.permissionDenied.rawValue {
                errorMessage = "Wrong passcode or account."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save(resetToXP: Bool = false) async {
        isSaving = true
        errorMessage = nil
        refreshedMessage = nil
        defer { isSaving = false }

        let trimmedLevel = levelText.trimmingCharacters(in: .whitespaces)
        let trimmedPrestige = prestigeText.trimmingCharacters(in: .whitespaces)
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        var payload: [String: Any] = [
            "passcode": passcode as NSString,
            "targetUid": user.uid as NSString,
        ]

        if resetToXP {
            payload["level"] = NSNull()
            payload["prestige"] = NSNull()
        } else {
            if levelEdited, let newLevel = Int(trimmedLevel) {
                payload["level"] = NSNumber(value: newLevel)
            }
            if prestigeEdited, let newPrestige = Int(trimmedPrestige) {
                payload["prestige"] = NSNumber(value: newPrestige)
            }
        }

        let initialTitle = user.adminEquippedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle != initialTitle {
            payload["equippedTitle"] = trimmedTitle.isEmpty ? NSNull() : (trimmedTitle as NSString)
        }

        let initialCountry = user.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmedCountry != initialCountry {
            payload["countryCode"] = trimmedCountry.isEmpty ? NSNull() : (trimmedCountry as NSString)
        }

        if payload.count <= 2 {
            errorMessage = "No changes to save."
            return
        }

        do {
            let result = try await functions.httpsCallable("adminSetUserProgression").call(payload)
            var updated = user
            if let data = result.data as? [String: Any] {
                updated.adminFloorLevel = intValue(data["adminFloorLevel"])
                updated.adminFloorPrestige = intValue(data["adminFloorPrestige"])
                updated.adminEquippedTitle = data["adminEquippedTitle"] as? String ?? ""
                updated.countryCode = (data["countryCode"] as? String ?? "").uppercased()
                if let lvl = intValue(data["level"]) { updated.level = lvl }
                if let pres = intValue(data["prestige"]) { updated.prestige = pres }
                updated.equippedTitle = data["equippedTitle"] as? String ?? updated.equippedTitle
            }
            onSaved(updated)
            if user.uid == currentUid {
                // Bounded wait: if the post-save cloud pull ever hangs (flaky
                // network, stuck listener, etc.) this must not leave Save
                // permanently disabled — fall through after a few seconds
                // either way so the sheet can still dismiss.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    var didResume = false
                    let resumeOnce = {
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume()
                    }
                    cloudSync.pullFromCloud { resumeOnce() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { resumeOnce() }
                }
            }
            if resetToXP {
                if let data = result.data as? [String: Any] {
                    if let lvl = intValue(data["level"]) { levelText = "\(lvl)" }
                    if let pres = intValue(data["prestige"]) { prestigeText = "\(pres)" }
                }
                refreshedMessage = "Reset to shift-derived progression."
                return
            }
            dismiss()
        } catch {
            let ns = error as NSError
            if ns.domain == FunctionsErrorDomain,
               ns.code == FunctionsErrorCode.permissionDenied.rawValue {
                errorMessage = "Wrong passcode or account."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func intValue(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let v = any as? Int64 { return Int(v) }
        if let v = any as? NSNumber { return v.intValue }
        return nil
    }

    private func adminCountryLabel(for code: String) -> String {
        let upper = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return "Not set" }
        return Locale.current.localizedString(forRegionCode: upper) ?? upper
    }

    private var accountFooterText: String {
        if let copiedField {
            return "Copied \(copiedField.lowercased())."
        }
        let activitySource = user.lastActiveFromPresence
            ? "Last active is their most recent time with the app open."
            : "Last active falls back to a sign-in token refresh here — this account has no presence record yet, so treat it as approximate."
        return "\(activitySource) Tap a row to copy it. A blank friend code means the account signed up but hasn't opened the app while signed in yet — the code is stamped on first authenticated launch."
    }

    /// A read-only detail row that copies its value on tap. Values that aren't
    /// present render as plain text so there's nothing to tap and copy "—".
    @ViewBuilder
    private func copyRow(_ label: String, _ value: String, copyable: Bool) -> some View {
        if copyable {
            Button {
                UIPasteboard.general.string = value
                Haptics.lightTap()
                withAnimation { copiedField = label }
            } label: {
                HStack {
                    Text(label)
                        .foregroundStyle(AppTheme.Colors.text)
                    Spacer()
                    Text(value)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: copiedField == label ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(copiedField == label ? AppTheme.Colors.success : AppTheme.Colors.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Text(label)
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
        }
    }

    private static func absoluteDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct AdminCountryPickerView: View {
    @Binding var selectedCode: String
    @State private var searchText = ""

    private var filteredRegions: [(code: String, name: String)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CountryFlag.selectableRegions }
        return CountryFlag.selectableRegions.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            ForEach(filteredRegions, id: \.code) { region in
                Button {
                    selectedCode = region.code
                } label: {
                    HStack(spacing: 12) {
                        if let flag = CountryFlag.emoji(for: region.code) {
                            Text(flag)
                                .font(.system(size: 22))
                        }
                        Text(region.name)
                            .foregroundStyle(AppTheme.Colors.text)
                        Spacer()
                        if region.code == selectedCode.uppercased() {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search countries")
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Country flag")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Verified inbox

/// Pending verified-mark submissions, populated by the `submitVerifiedProof`
/// callable when users submit review screenshots in-app. Approving grants the
/// mark; either outcome removes the row.
struct AdminVerifiedInboxView: View {
    let passcode: String
    /// Lets the parent list flip its cached row without a full reload.
    var onApproved: (String) -> Void

    @State private var items: [InboxItem] = []
    @State private var isLoading = true
    @State private var resolvingUid: String?
    @State private var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")

    struct InboxItem: Identifiable {
        let uid: String
        let displayName: String
        let friendCode: String
        let photoURL: String
        let submittedAt: Date?
        var id: String { uid }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(AppTheme.Colors.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    VerifiedBadgeView(variant: .static, size: 40)
                        .opacity(0.5)
                    Text("No submissions waiting")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        inboxRow(item)
                            .listRowBackground(AppTheme.Colors.card)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.danger)
                            .listRowBackground(AppTheme.Colors.card)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Verified inbox")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func inboxRow(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: 8) {
                Text(item.displayName.isEmpty ? "(no name)" : item.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                if !item.friendCode.isEmpty {
                    Text(item.friendCode)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
                Spacer(minLength: 0)
                if let date = item.submittedAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                }
            }

            // The screenshot itself — the whole point of the row.
            AsyncImage(url: URL(string: item.photoURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Label("Couldn't load screenshot", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                }
            }
            .frame(maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

            HStack(spacing: AppSpacing.sm) {
                Button {
                    Task { await resolve(item, approve: true) }
                } label: {
                    HStack(spacing: 6) {
                        if resolvingUid == item.uid { ProgressView().tint(.white) }
                        Text("Approve")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppTheme.Colors.accent))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await resolve(item, approve: false) }
                } label: {
                    Text("Reject")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppTheme.Colors.danger.opacity(0.16)))
                        .foregroundStyle(AppTheme.Colors.danger)
                }
                .buttonStyle(.plain)
            }
            .disabled(resolvingUid != nil)
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        errorMessage = nil
        do {
            let result = try await functions.httpsCallable("adminListVerifiedInbox")
                .call(["passcode": passcode])
            let data = result.data as? [String: Any] ?? [:]
            let raw = data["items"] as? [[String: Any]] ?? []
            items = raw.map { dict in
                InboxItem(
                    uid: dict["uid"] as? String ?? "",
                    displayName: dict["displayName"] as? String ?? "",
                    friendCode: dict["friendCode"] as? String ?? "",
                    photoURL: dict["photoURL"] as? String ?? "",
                    submittedAt: (dict["submittedAt"] as? Double).map {
                        Date(timeIntervalSince1970: $0 / 1000)
                    }
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func resolve(_ item: InboxItem, approve: Bool) async {
        resolvingUid = item.uid
        defer { resolvingUid = nil }
        do {
            _ = try await functions.httpsCallable("adminResolveVerifiedProof")
                .call(["passcode": passcode, "targetUid": item.uid, "approve": approve])
            if approve {
                Haptics.success()
                onApproved(item.uid)
            } else {
                Haptics.mediumTap()
            }
            withAnimation(.snappy) {
                items.removeAll { $0.uid == item.uid }
            }
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Announcement composer

/// Publishes the one live app-wide announcement. Every user sees it once on
/// their next app open; the "Update" kind routes its button to the App Store
/// listing. Publishing replaces the previous announcement, Clear takes it
/// down for anyone who hasn't seen it yet.
struct AdminAnnouncementView: View {
    let passcode: String

    @State private var title = "Update available!"
    @State private var message = "A new version of Hour Tracker is out with new features and fixes. Update now to get the latest."
    @State private var isUpdatePrompt = true
    @State private var isPublishing = false
    @State private var isClearing = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                TextField("Message", text: $message, axis: .vertical)
                    .lineLimit(3...8)
                Toggle(isOn: $isUpdatePrompt) {
                    Text("Update button (opens the App Store)")
                }
            } header: {
                Text("Compose")
            } footer: {
                Text("Shows once to every user the next time they open the app — a card like the country-flag prompt, with \(isUpdatePrompt ? "an Update Now button that opens the App Store listing" : "a Got it button") and Not Now. Publishing again later re-prompts everyone.")
            }
            .listRowBackground(AppTheme.Colors.card)

            Section {
                Button {
                    Task { await publish() }
                } label: {
                    HStack {
                        if isPublishing { ProgressView() }
                        Text(isPublishing ? "Publishing…" : "Publish to all users")
                            .fontWeight(.bold)
                    }
                }
                .disabled(isPublishing || isClearing
                          || title.trimmingCharacters(in: .whitespaces).isEmpty
                          || message.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(role: .destructive) {
                    Task { await clear() }
                } label: {
                    HStack {
                        if isClearing { ProgressView() }
                        Text(isClearing ? "Clearing…" : "Clear current announcement")
                    }
                }
                .disabled(isPublishing || isClearing)
            } footer: {
                if let statusMessage {
                    Text(statusMessage).foregroundStyle(AppTheme.Colors.success)
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppTheme.Colors.danger)
                }
            }
            .listRowBackground(AppTheme.Colors.card)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Announcement")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func publish() async {
        isPublishing = true
        statusMessage = nil
        errorMessage = nil
        defer { isPublishing = false }
        do {
            _ = try await functions.httpsCallable("adminPublishAnnouncement").call([
                "passcode": passcode,
                "title": title.trimmingCharacters(in: .whitespaces),
                "message": message.trimmingCharacters(in: .whitespaces),
                "kind": isUpdatePrompt ? "update" : "info",
            ])
            Haptics.success()
            statusMessage = "Published. Every user sees it on their next app open."
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }

    private func clear() async {
        isClearing = true
        statusMessage = nil
        errorMessage = nil
        defer { isClearing = false }
        do {
            _ = try await functions.httpsCallable("adminClearAnnouncement")
                .call(["passcode": passcode])
            Haptics.success()
            statusMessage = "Announcement cleared."
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }
}

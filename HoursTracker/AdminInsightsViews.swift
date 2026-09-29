import FirebaseFunctions
import SwiftUI

// MARK: - Feature ideas

/// Admin: every idea sent from the Home "What should we add next?" box,
/// newest first. Read through `adminListSuggestions` (clients can't read
/// the collection directly).
struct AdminSuggestionsView: View {
    let passcode: String

    @State private var items: [Item] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")

    struct Item: Identifiable {
        let id: String
        let username: String
        let text: String
        let appVersion: String
        let createdAt: Date?
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .listRowBackground(AppTheme.Colors.card)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading ideas…").foregroundStyle(AppTheme.Colors.subtext)
                }
                .listRowBackground(AppTheme.Colors.card)
            } else if items.isEmpty {
                Text("No ideas yet. They'll show up here as users send them.")
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .listRowBackground(AppTheme.Colors.card)
            } else {
                Section("\(items.count) \(items.count == 1 ? "idea" : "ideas")") {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.text)
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.Colors.text)
                                .textSelection(.enabled)
                            HStack(spacing: 6) {
                                Text(item.username.isEmpty ? "No username" : "@\(item.username)")
                                if !item.appVersion.isEmpty { Text("· v\(item.appVersion)") }
                                Spacer()
                                if let date = item.createdAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.Colors.subtext)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(AppTheme.Colors.card)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Feature ideas")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            let result = try await functions.httpsCallable("adminListSuggestions")
                .call(["passcode": passcode])
            let data = result.data as? [String: Any] ?? [:]
            let raw = data["items"] as? [[String: Any]] ?? []
            items = raw.map { dict in
                Item(
                    id: dict["id"] as? String ?? UUID().uuidString,
                    username: dict["username"] as? String ?? "",
                    text: dict["text"] as? String ?? "",
                    appVersion: dict["appVersion"] as? String ?? "",
                    createdAt: (dict["createdAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - App versions

/// Admin: who is on the newest release and who isn't, by name — the
/// overview chip only gives the count.
struct AdminVersionsView: View {
    let users: [AdminUser]

    private var latest: String? {
        users.map(\.appVersion).filter { !$0.isEmpty }
            .max(by: { AdminPanelView.versionIsOrderedBefore($0, $1) })
    }

    private func name(_ user: AdminUser) -> String {
        user.username.isEmpty ? user.displayName : "@\(user.username)"
    }

    private var onLatest: [AdminUser] {
        guard let latest else { return [] }
        return users.filter { $0.appVersion == latest }
            .sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
    }

    /// Everyone else, newest version first, so "one release behind" sits
    /// above people who haven't updated in months.
    private var behind: [AdminUser] {
        users.filter { $0.appVersion != latest }
            .sorted { lhs, rhs in
                if lhs.appVersion != rhs.appVersion {
                    return AdminPanelView.versionIsOrderedBefore(rhs.appVersion, lhs.appVersion)
                }
                return (lhs.lastActiveAt ?? .distantPast) > (rhs.lastActiveAt ?? .distantPast)
            }
    }

    var body: some View {
        List {
            if let latest {
                Section("On v\(latest) · \(onLatest.count)") {
                    ForEach(onLatest) { row($0) }
                }
                .listRowBackground(AppTheme.Colors.card)
            }
            Section("Not on the latest · \(behind.count)") {
                ForEach(behind) { row($0) }
            }
            .listRowBackground(AppTheme.Colors.card)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("App versions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ user: AdminUser) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name(user))
                    .foregroundStyle(AppTheme.Colors.text)
                    .lineLimit(1)
                if let active = user.lastActiveAt {
                    Text("Active \(active.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }
            Spacer()
            Text(user.appVersionDisplay)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(user.appVersion == latest ? AppTheme.Colors.success : AppTheme.Colors.subtext)
        }
    }
}

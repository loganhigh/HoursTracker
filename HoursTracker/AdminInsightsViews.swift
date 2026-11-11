import SwiftUI

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

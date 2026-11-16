import SwiftUI
import FirebaseFirestore

// MARK: - Chat heart

/// Small heart after a supporter's name in Board Chat and DMs, in their
/// supporter colour. Nothing for everyone else.
struct SupporterHeart: View {
    let name: String
    var uid: String? = nil

    @ObservedObject private var supporters = SupporterRegistry.shared

    var body: some View {
        if !DeveloperConfig.isCEO(uid: uid), let style = supporters.style(name: name, uid: uid) {
            Image(systemName: "heart.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(style.color.solid)
                .accessibilityLabel("Supporter")
        }
    }
}

// MARK: - Thanks wall

/// Everyone who has left a tip, in their supporter colours. Names only —
/// amounts are never shown.
struct SupporterThanksWall: View {
    @State private var names: [(uid: String, name: String)] = []
    @State private var loaded = false

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("Thanks to our supporters")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(AppColors.subtext)
            if !loaded {
                ProgressView()
            } else if names.isEmpty {
                Text("Be the first name here.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.faint)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(names, id: \.uid) { person in
                        HStack(spacing: 3) {
                            PrestigeNameText(name: "@\(person.name)", prestige: 0,
                                             font: .footnote.weight(.bold), uid: person.uid)
                            SupporterHeart(name: person.name, uid: person.uid)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppColors.card))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task { await load() }
    }

    private func load() async {
        let query = Firestore.firestore().collection("publicProfiles")
            .whereField("isSupporter", isEqualTo: true)
            .limit(to: 300)
        // Cached copy first so the wall shows instantly on return visits.
        if let cached = try? await query.getDocuments(source: .cache), !cached.documents.isEmpty {
            apply(cached)
            loaded = true
        }
        // A server read can stall for a long time on a flaky connection and
        // left the spinner going forever. Give up waiting after 8 seconds.
        // The fetch runs on its own (it can't be cancelled), and the wall
        // still fills in if it lands after the cutoff.
        Task { @MainActor in
            if let fresh = try? await query.getDocuments(source: .server) { apply(fresh) }
            loaded = true
        }
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        loaded = true
    }

    private func apply(_ snap: QuerySnapshot) {
        var list: [(uid: String, name: String)] = []
        for doc in snap.documents {
            let data = doc.data()
            let name = Username.normalize(data["username"] as? String ?? "")
            guard !name.isEmpty else { continue }
            SupporterRegistry.shared.record(name: name, isSupporter: true, uid: doc.documentID,
                                            supporter: data["supporter"])
            list.append((doc.documentID, name))
        }
        names = list.sorted { $0.name < $1.name }
    }
}

/// Wrapping row layout for the thanks wall's name chips, centred per line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(for: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

import SwiftUI
import FirebaseFunctions

/// Every tip anyone has left, newest first, with totals per currency. Apple
/// reports sales but never who paid; this is the app's own ledger, written
/// by each device when a tip goes through (see SupporterRegistry.recordTip).
struct AdminTipsView: View {
    let passcode: String

    struct Tip: Identifiable {
        let id: String
        let uid: String
        let name: String
        let productName: String
        let amount: Double
        let currency: String
        let appVersion: String
        let createdAt: Date?
    }

    @State private var tips: [Tip] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")

    /// "$12.96 CAD · $4.99 USD" — one total per currency, largest first.
    private var totals: [(currency: String, amount: Double, count: Int)] {
        var byCurrency: [String: (Double, Int)] = [:]
        for tip in tips {
            let key = tip.currency.isEmpty ? "?" : tip.currency
            let cur = byCurrency[key] ?? (0, 0)
            byCurrency[key] = (cur.0 + tip.amount, cur.1 + 1)
        }
        return byCurrency.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                .listRowBackground(AppTheme.Colors.card)
            } else if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(AppTheme.Colors.danger)
                }
                .listRowBackground(AppTheme.Colors.card)
            } else if tips.isEmpty {
                Section {
                    Text("No tips yet.").foregroundStyle(AppTheme.Colors.subtext)
                }
                .listRowBackground(AppTheme.Colors.card)
            } else {
                Section("Totals") {
                    ForEach(totals, id: \.currency) { total in
                        HStack {
                            Text(total.currency)
                            Spacer()
                            Text("\(Self.money(total.amount, total.currency))  ·  \(total.count) \(total.count == 1 ? "tip" : "tips")")
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                    }
                }
                .listRowBackground(AppTheme.Colors.card)

                Section("Tips") {
                    ForEach(tips) { tip in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.name.isEmpty ? "(no name)" : tip.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppTheme.Colors.text)
                                Text([tip.productName, tip.createdAt.map { Self.date($0) }, tip.appVersion.isEmpty ? nil : "v\(tip.appVersion)"]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.Colors.subtext)
                            }
                            Spacer()
                            Text(Self.money(tip.amount, tip.currency))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.Colors.accent)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(AppTheme.Colors.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Tips")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = tips.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await functions.httpsCallable("adminListTips").call(["passcode": passcode])
            guard let dict = result.data as? [String: Any],
                  let rows = dict["tips"] as? [[String: Any]] else {
                errorMessage = "Unexpected response."
                return
            }
            tips = rows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                let ms = (row["createdAt"] as? NSNumber)?.doubleValue
                return Tip(
                    id: id,
                    uid: row["uid"] as? String ?? "",
                    name: row["name"] as? String ?? "",
                    productName: row["productName"] as? String ?? "",
                    amount: (row["amount"] as? NSNumber)?.doubleValue ?? 0,
                    currency: row["currency"] as? String ?? "",
                    appVersion: row["appVersion"] as? String ?? "",
                    createdAt: ms.map { Date(timeIntervalSince1970: $0 / 1000) }
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func money(_ amount: Double, _ currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency.isEmpty ? "USD" : currency
        return f.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    private static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

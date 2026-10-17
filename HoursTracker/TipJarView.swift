import SwiftUI
import Combine
import StoreKit

/// Consumable tips ("Support Hour Tracker"). Tips unlock nothing — they are
/// finished on purchase and never touch the Pro entitlement.
@MainActor
final class TipJarManager: ObservableObject {
    static let shared = TipJarManager()

    /// Fixed-price consumables, one per tip button.
    static let tipProductIDs = [
        "com.loganh.HourTracker.tip.025",   // $0.99 (id predates the price)
        "com.loganh.HourTracker.tip.199",
        "com.loganh.HourTracker.tip.499",
        "com.loganh.HourTracker.tip.999",
        "com.loganh.HourTracker.tip.1999",
        "com.loganh.HourTracker.tip.4999"
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var purchasingID: String?
    @Published private(set) var didTip = false
    @Published var errorMessage: String?

    func load() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.tipProductIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Couldn't load tips. Check your connection and try again."
        }
    }

    func tip(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false; purchasingID = nil }
        purchasingID = product.id
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "That purchase couldn't be verified."
                    return
                }
                await transaction.finish()
                SupporterRegistry.shared.recordTip(transaction: transaction, product: product)
                didTip = true
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "The tip didn't go through. You weren't charged."
        }
    }
}

struct TipJarView: View {
    @StateObject private var manager = TipJarManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xl) {
                Spacer(minLength: AppSpacing.lg)

                // Heart while asking, cheering once the tip lands.
                OwlView(pose: manager.didTip ? .cheer : .heart, size: .emptyState)

                VStack(spacing: AppSpacing.sm) {
                    Text(manager.didTip ? "Thank you!" : "Support Hour Tracker")
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                    Text(manager.didTip
                         ? "Your username now shimmers. That genuinely helps keep Hour Tracker running."
                         : "Hour Tracker is free to use. If you find it useful and want to help with the cost of keeping it running, you can leave a small tip. Your support helps keep Hour Tracker free and ad-free!")
                        .appText(.body)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppSpacing.lg)

                tipButtons

                Spacer()
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await manager.load() }
            .alert("Tip Jar", isPresented: Binding(
                get: { manager.errorMessage != nil },
                set: { if !$0 { manager.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(manager.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var tipButtons: some View {
        if manager.isLoading {
            ProgressView()
        } else if manager.products.isEmpty {
            Button("Try Again") { Task { await manager.load() } }
                .appText(.headline)
        } else {
            let rows = stride(from: 0, to: manager.products.count, by: 3).map {
                Array(manager.products[$0..<min($0 + 3, manager.products.count)])
            }
            VStack(spacing: AppSpacing.sm) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: AppSpacing.sm) {
                        // A short last row keeps its buttons the same size,
                        // centred, instead of stretching them.
                        if row.count < 3 { Color.clear.frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1) }
                        ForEach(row, id: \.id) { product in
                            tipButton(product)
                        }
                        if row.count < 3 { Color.clear.frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1) }
                    }
                }
            }
        }
    }

    private func tipButton(_ product: Product) -> some View {
        Button {
            Haptics.lightTap()
            Task { await manager.tip(product) }
        } label: {
            ZStack {
                if manager.purchasingID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .appText(.headline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(AppColors.textOnAccent)
            .background(AppColors.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(manager.isPurchasing || !AppStore.canMakePayments)
    }
}

/// Home-screen entry to the tip jar, in the same eyebrow-plus-card layout as
/// the other Home sections. Owns its own sheet so Home only has to place it.
struct TipJarHomeCard: View {
    @State private var showingTipJar = false

    var body: some View {
        VStack(spacing: 12) {
            SectionEyebrow("Support Hour Tracker", subtitle: "Help keep it free and ad-free")

            Button {
                Haptics.lightTap()
                showingTipJar = true
            } label: {
                VStack(spacing: AppSpacing.sm) {
                    OwlView(pose: .heart, size: .companion)
                    Text("Hour Tracker is free to use. If you find it useful, you can leave a small tip to help cover the cost of keeping it running.")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Leave a tip")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(AppColors.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: AppChunk.radius, style: .continuous).fill(AppColors.accent))
                        .padding(.top, AppSpacing.xxs)
                }
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.md)
                .chunkyCard()
            }
            .buttonStyle(PremiumPressStyle())
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingTipJar) { TipJarView() }
    }
}

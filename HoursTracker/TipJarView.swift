import SwiftUI
import Combine
import StoreKit

/// Consumable tips ("Support Hour Tracker"). Tips unlock nothing — they are
/// finished on purchase and never touch the Pro entitlement.
@MainActor
final class TipJarManager: ObservableObject {
    static let shared = TipJarManager()

    static let tipProductIDs = [
        "com.loganh.HourTracker.tip.025",
        "com.loganh.HourTracker.tip.050",
        "com.loganh.HourTracker.tip.100"
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
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
        guard purchasingID == nil else { return }
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    didTip = true
                } else {
                    errorMessage = "That purchase couldn't be verified."
                }
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

                Image(systemName: manager.didTip ? "heart.fill" : "heart")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .symbolEffect(.bounce, value: manager.didTip)

                VStack(spacing: AppSpacing.sm) {
                    Text(manager.didTip ? "Thank you!" : "Support Hour Tracker")
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                    Text(manager.didTip
                         ? "That genuinely helps keep Hour Tracker running."
                         : "Hour Tracker is free to use. If you find it useful and want to help with the cost of keeping it running, you can leave a small tip.")
                        .appText(.body)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppSpacing.lg)

                tipButtons

                Text("Tips are optional and unlock nothing.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.faint)

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
            HStack(spacing: AppSpacing.sm) {
                ForEach(manager.products, id: \.id) { product in
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
                    .disabled(manager.purchasingID != nil || !AppStore.canMakePayments)
                }
            }
        }
    }
}

/// Home-screen entry to the tip jar. Owns its own sheet so Home only has to
/// place it.
struct TipJarHomeCard: View {
    @State private var showingTipJar = false

    var body: some View {
        Button {
            Haptics.lightTap()
            showingTipJar = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(AppColors.accentMuted))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Support Hour Tracker")
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                    Text("Free to use. Leave a small tip to help cover the costs.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: AppSpacing.xs)
                SettingsChevron()
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingTipJar) { TipJarView() }
    }
}

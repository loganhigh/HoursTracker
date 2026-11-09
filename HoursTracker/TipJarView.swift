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
            ScrollView {
            VStack(spacing: AppSpacing.xl) {

                // Heart while asking, cheering once the tip lands.
                OwlView(pose: manager.didTip ? .cheer : .heart, size: .emptyState)

                VStack(spacing: AppSpacing.sm) {
                    Text(manager.didTip ? "Thank you!" : "Support Hour Tracker")
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                    Text(manager.didTip
                         ? "Your name now shimmers in supporter blue. That genuinely helps keep Hour Tracker running."
                         : "Hour Tracker is free to use. If you find it useful and want to help with the cost of keeping it running, you can leave a small tip. Your support helps keep Hour Tracker free and ad-free!")
                        .appText(.body)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppSpacing.lg)

                perksCard

                choicesCard

                tipButtons

                SupporterThanksWall()
                    .padding(.top, AppSpacing.sm)
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity)
            }
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

    @ObservedObject private var supporters = SupporterRegistry.shared

    /// What tips unlock, by total tipped — so people know where the coloured
    /// names, hearts and rings around the app come from. Keep in step with
    /// functions/src/supporter.js.
    private var perksCard: some View {
        let total = supporters.selfStyle.total
        let tipped = supporters.selfIsSupporter
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(tipped ? "Your supporter perks" : "What tips unlock")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(AppColors.subtext)
            perk(icon: "sparkles", title: "Supporter name", detail: "Your username turns shimmering blue everywhere",
                 tier: "Any tip", unlocked: tipped, highlight: true)
            perk(icon: "heart.fill", title: "Badge & chat heart",
                 detail: "A Supporter badge on your profile and a heart by your name in chat",
                 tier: "Any tip", unlocked: tipped)
            perk(icon: "hands.clap.fill", title: "Thanks wall", detail: "Your name on the supporters list below",
                 tier: "Any tip", unlocked: tipped)
            perk(icon: "paintpalette.fill", title: "Pick your name colour",
                 detail: "Blue, purple, emerald or rose",
                 tier: "$5 total", unlocked: tipped && total >= SupporterStyle.colorUnlockTotal)
            perk(icon: "circle.dashed", title: "Animated photo ring",
                 detail: "A ring in your colour turns around your photo",
                 tier: "$20 total", unlocked: tipped && total >= SupporterStyle.ringUnlockTotal)
            Text("Tips add up, and perks never expire.")
                .appText(.caption)
                .foregroundStyle(AppColors.faint)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColors.card))
    }

    private func perk(icon: String, title: String, detail: String, tier: String,
                      unlocked: Bool, highlight: Bool = false) -> some View {
        let color = supporters.selfStyle.color
        return HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color.solid)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.solid.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if highlight {
                        Text(title).foregroundStyle(LinearGradient(colors: color.gradient,
                                                                   startPoint: .leading, endPoint: .trailing))
                    } else {
                        Text(title).foregroundStyle(AppColors.text)
                    }
                }
                .font(.system(.callout, design: .rounded, weight: .bold))
                Text(detail)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
            Spacer(minLength: 4)
            if unlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.positive)
                    .accessibilityLabel("Unlocked")
            } else {
                Text(tier)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.subtext)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppColors.bg))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Supporters' choices: colour ($5+) and, at Legend prestige, whether
    /// the name shows Legend's colour or theirs.
    @ViewBuilder
    private var choicesCard: some View {
        if supporters.selfIsSupporter {
            let style = supporters.selfStyle
            let colorUnlocked = style.total >= SupporterStyle.colorUnlockTotal
            let isLegend = (HoursStore.current?.displayedPrestige ?? 0) > 10
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Name colour")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(AppColors.subtext)
                HStack(spacing: AppSpacing.sm) {
                    ForEach(SupporterColor.allCases) { option in
                        let chosen = style.color == option
                        Button {
                            Haptics.lightTap()
                            supporters.saveChoices(color: option)
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(LinearGradient(colors: option.gradient,
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 36, height: 36)
                                    .overlay(Circle().stroke(AppColors.text, lineWidth: chosen ? 2 : 0))
                                Text(option.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(chosen ? AppColors.text : AppColors.subtext)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .disabled(!colorUnlocked && option != .blue)
                        .opacity(!colorUnlocked && option != .blue ? 0.35 : 1)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
                if !colorUnlocked {
                    Text("Tip \(Self.money(SupporterStyle.colorUnlockTotal - style.total)) more in total to pick a colour.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.faint)
                }
                if isLegend {
                    Toggle(isOn: Binding(
                        get: { style.prefersColor },
                        set: { supporters.saveChoices(prefersColor: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Show supporter colour at Legend")
                                .font(.system(.callout, design: .rounded, weight: .bold))
                                .foregroundStyle(AppColors.text)
                            Text("Off shows your Legend prestige colour instead.")
                                .appText(.caption)
                                .foregroundStyle(AppColors.subtext)
                        }
                    }
                    .tint(AppColors.accent)
                    .padding(.top, AppSpacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColors.card))
        }
    }

    private static func money(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: max(0, amount))) ?? String(format: "$%.2f", max(0, amount))
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
        VStack(spacing: AppSpacing.sm) {
            HomeSectionHeader("Support Hour Tracker", subtitle: "Help keep it free and ad-free")

            VStack(spacing: 0) {
                OwlView(pose: .heart, size: .companion)
                Text("Hour Tracker is free to use.")
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(AppColors.text)
                    .padding(.top, AppSpacing.sm)
                Text("If you find it useful, a small tip helps cover the cost of keeping it running — and turns your name supporter blue.")
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Button("Leave a tip") {
                    Haptics.lightTap()
                    showingTipJar = true
                }
                .buttonStyle(QuietSectionButtonStyle(fullWidth: false))
                .padding(.top, AppSpacing.md)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .padding(.horizontal, AppSpacing.lg)
            .homeCard()
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingTipJar) { TipJarView() }
    }
}

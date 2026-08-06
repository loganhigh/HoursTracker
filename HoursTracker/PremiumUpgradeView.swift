import SwiftUI
import StoreKit

/// Paywall for the "Hour Tracker Pro" subscription (monthly / yearly).
struct PremiumUpgradeView: View {
    @ObservedObject private var premium = PremiumManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedProductID: String?
    @State private var message: String?
    @State private var isError = false

    private let benefits: [(icon: String, title: String, subtitle: String)] = [
        ("clock.badge.checkmark.fill", "Live Shift Tracking", "Clock in and out with a running timer."),
        ("doc.richtext.fill", "Professional PDF Reports", "Export polished reports with your company branding."),
        ("hand.raised.slash.fill", "Remove all ads", "Enjoy a clean, distraction-free app.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    header

                    VStack(spacing: AppSpacing.sm) {
                        ForEach(benefits, id: \.title) { benefit in
                            benefitRow(benefit)
                        }
                    }

                    if premium.isPremium {
                        activeState
                    } else {
                        planPicker
                        purchaseControls
                    }

                    if let message {
                        Text(message)
                            .appText(.caption)
                            .foregroundStyle(isError ? AppColors.negative : AppColors.accent)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    LegalLinksSection()

                    #if DEBUG
                    debugControls
                    #endif
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Hour Tracker Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if premium.products.isEmpty {
                await premium.loadProducts()
            }
            if selectedProductID == nil {
                selectedProductID = premium.products.first(where: { $0.id == PremiumManager.yearlyProductID })?.id
                    ?? premium.products.first?.id
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(AppColors.accentGradient)
                .shadow(color: reduceMotion ? .clear : AppColors.glow, radius: 12)
            Text("Hour Tracker Pro")
                .appText(.title)
                .foregroundStyle(AppColors.text)
            Text("Everything you need to track, report, and get paid right.")
                .appText(.subheadline)
                .foregroundStyle(AppColors.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xs)
    }

    private func benefitRow(_ benefit: (icon: String, title: String, subtitle: String)) -> some View {
        HStack(spacing: AppSpacing.sm) {
            SettingsIconSquare(icon: benefit.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                Text(benefit.subtitle)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Plan picker

    private var planPicker: some View {
        VStack(spacing: AppSpacing.xs) {
            if premium.products.isEmpty {
                ProgressView()
                    .tint(AppColors.accent)
                    .padding(.vertical, AppSpacing.md)
            } else {
                ForEach(premium.products, id: \.id) { product in
                    PremiumPlanCard(
                        product: product,
                        isSelected: selectedProductID == product.id,
                        savingsText: savingsText(for: product)
                    ) {
                        Haptics.lightTap()
                        withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
                            selectedProductID = product.id
                        }
                    }
                }
            }
        }
    }

    /// Computed (never hardcoded) savings badge for the yearly plan, derived
    /// from the live monthly price vs. the yearly price.
    private func savingsText(for product: Product) -> String? {
        guard product.id == PremiumManager.yearlyProductID,
              let monthly = premium.products.first(where: { $0.id == PremiumManager.monthlyProductID }) else {
            return nil
        }
        let yearlyIfMonthly = monthly.price * 12
        guard yearlyIfMonthly > product.price else { return nil }
        let savingsFraction = (yearlyIfMonthly - product.price) / yearlyIfMonthly
        let percent = Int((NSDecimalNumber(decimal: savingsFraction).doubleValue * 100).rounded())
        guard percent > 0 else { return nil }
        return "Save \(percent)%"
    }

    // MARK: - Purchase controls

    private var purchaseControls: some View {
        VStack(spacing: AppSpacing.sm) {
            Button {
                Task { await runPurchase() }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    if premium.isPurchasing {
                        ProgressView().tint(AppColors.textOnAccent)
                    }
                    Text(purchaseButtonTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(premium.isPurchasing || !premium.purchasesAvailable || selectedProduct == nil)

            Button("Restore Purchases") {
                Task { await runRestore() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppColors.subtext)
            .disabled(premium.isPurchasing || !premium.purchasesAvailable)

            if !premium.purchasesAvailable {
                Text("In-app purchases aren't available on this device right now.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.faint)
                    .multilineTextAlignment(.center)
            }

            Text("Cancel anytime in Settings. Subscription auto-renews until canceled.")
                .appText(.caption)
                .foregroundStyle(AppColors.faint)
                .multilineTextAlignment(.center)
        }
    }

    private var selectedProduct: Product? {
        premium.products.first { $0.id == selectedProductID }
    }

    private var purchaseButtonTitle: String {
        guard let product = selectedProduct else { return "Subscribe" }
        return "Subscribe — \(product.displayPrice)"
    }

    // MARK: - Active state

    private var activeState: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.positive)
            Text(premium.activeSubscription?.settingsStatusLine ?? "You're on Hour Tracker Pro")
                .appText(.headline)
                .foregroundStyle(AppColors.text)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.positive.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.positive.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: - Actions

    private func runPurchase() async {
        guard let product = selectedProduct else { return }
        message = nil
        let ok = await premium.purchase(product)
        isError = !ok
        message = ok ? "Welcome to Pro!" : "Purchase didn't complete. Please try again."
    }

    private func runRestore() async {
        message = nil
        let ok = await premium.restore()
        isError = !ok
        message = ok ? "Purchases restored." : "No previous purchase found."
    }

    #if DEBUG
    private var debugControls: some View {
        VStack(spacing: AppSpacing.xs) {
            Divider().opacity(0.3)
            Text("DEBUG")
                .appText(.eyebrow)
                .foregroundStyle(AppColors.faint)
            Button(premium.isPremium ? "Debug: turn OFF Pro" : "Debug: turn ON Pro") {
                premium.debugSetPremium(!premium.isPremium)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.accent)
        }
    }
    #endif
}

// MARK: - Plan card

/// A single selectable monthly/yearly plan row.
private struct PremiumPlanCard: View {
    let product: Product
    let isSelected: Bool
    let savingsText: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.faint)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppSpacing.xxs) {
                        Text(planName)
                            .appText(.headline)
                            .foregroundStyle(AppColors.text)
                        if let savingsText {
                            Text(savingsText)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textOnAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(AppColors.accent))
                        }
                    }
                    Text(billingPeriodText)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }

                Spacer(minLength: AppSpacing.xs)

                Text(product.displayPrice)
                    .appText(.metricValue)
                    .foregroundStyle(AppColors.text)
            }
            .padding(AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(isSelected ? AppColors.accent.opacity(0.1) : AppColors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(isSelected ? AppColors.accent.opacity(0.6) : AppColors.stroke, lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(PremiumPressStyle())
    }

    private var planName: String {
        product.id == PremiumManager.yearlyProductID ? "Yearly" : "Monthly"
    }

    private var billingPeriodText: String {
        product.id == PremiumManager.yearlyProductID ? "Billed once a year" : "Billed once a month"
    }
}

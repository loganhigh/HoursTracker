import SwiftUI

/// Paywall for the one-time "Hour Tracker Pro" lifetime unlock.
struct PremiumUpgradeView: View {
    @ObservedObject private var premium = PremiumManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var message: String?
    @State private var isError = false

    private let benefits: [(icon: String, title: String, subtitle: String)] = [
        ("hand.raised.slash.fill", "Remove all ads", "Enjoy a clean, distraction-free app forever."),
        ("bolt.heart.fill", "Support development", "Help keep new features coming."),
        ("infinity", "One-time purchase", "Pay once, yours for life — no subscription.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    header

                    VStack(spacing: 12) {
                        ForEach(benefits, id: \.title) { benefit in
                            benefitRow(benefit)
                        }
                    }

                    if premium.isPremium {
                        activeState
                    } else {
                        purchaseControls
                    }

                    if let message {
                        Text(message)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isError ? .red : AppTheme.Colors.accent)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    LegalLinksSection()

                    #if DEBUG
                    debugControls
                    #endif
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, 20)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Hour Tracker Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(AppTheme.Colors.accentGradient)
                .shadow(color: AppTheme.Colors.glow, radius: 12)
            Text("Go Pro")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
            Text("Remove ads forever with a one-time unlock.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func benefitRow(_ benefit: (icon: String, title: String, subtitle: String)) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(AppTheme.Colors.accent.opacity(0.16)).frame(width: 44, height: 44)
                Image(systemName: benefit.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                Text(benefit.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.Colors.card)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.Colors.stroke, lineWidth: 1))
        )
    }

    private var purchaseControls: some View {
        VStack(spacing: 12) {
            Button {
                Task { await runPurchase() }
            } label: {
                HStack(spacing: 8) {
                    if premium.isPurchasing {
                        ProgressView().tint(.white)
                    }
                    Text(purchaseButtonTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.Colors.accentGradient)
                        .shadow(color: AppTheme.Colors.accent.opacity(0.5), radius: 12, y: 4)
                )
            }
            .buttonStyle(.plain)
            .disabled(premium.isPurchasing || !premium.purchasesAvailable)

            Button("Restore Purchases") {
                Task { await runRestore() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.subtext)
            .disabled(premium.isPurchasing || !premium.purchasesAvailable)

            if !premium.purchasesAvailable {
                Text("In-app purchases aren't available in this build yet.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.faint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var purchaseButtonTitle: String {
        if let price = premium.priceString { return "Unlock Pro — \(price)" }
        return "Unlock Pro"
    }

    private var activeState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.green)
            Text("You're Pro — thank you!")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.green.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.green.opacity(0.35), lineWidth: 1))
        )
    }

    private func runPurchase() async {
        message = nil
        let ok = await premium.purchase()
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
        VStack(spacing: 8) {
            Divider().opacity(0.3)
            Text("DEBUG")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.Colors.faint)
            Button(premium.isPremium ? "Debug: turn OFF Pro" : "Debug: turn ON Pro") {
                premium.debugSetPremium(!premium.isPremium)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.Colors.accent)
        }
    }
    #endif
}

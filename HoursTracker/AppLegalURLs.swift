import Foundation
import SwiftUI

/// Canonical legal and support URLs — must match App Store Connect entries.
enum AppLegalURLs {
    static let website = URL(string: "https://hourtracking.online")!
    static let support = URL(string: "https://hourtracking.online/support")!
    static let privacyPolicy = URL(string: "https://hourtracking.online/privacy")!
    static let termsOfUse = URL(string: "https://hourtracking.online/terms")!
}

/// Compact legal links — used in Settings and Account.
struct LegalLinksSection: View {
    @Environment(\.semanticColors) private var theme

    var body: some View {
        HStack(spacing: 10) {
            LegalLinkTile(
                title: "Privacy Policy",
                icon: "hand.raised.fill",
                url: AppLegalURLs.privacyPolicy
            )
            LegalLinkTile(
                title: "Terms of Use",
                icon: "doc.text.fill",
                url: AppLegalURLs.termsOfUse
            )
        }
    }
}

private struct LegalLinkTile: View {
    let title: String
    let icon: String
    let url: URL

    @Environment(\.semanticColors) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Haptics.lightTap()
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text("View")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(theme.accent.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.cardSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.border.opacity(0.55), lineWidth: 0.5)
            )
        }
        .buttonStyle(PremiumPressStyle())
    }
}

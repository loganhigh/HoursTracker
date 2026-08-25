import SwiftUI

/// The January entry point to Wrapped, shown at the top of Home.
///
/// Visually it borrows Wrapped's own dark/gold treatment rather than the
/// app's standard card, so it reads as a doorway into a different
/// experience instead of another stat tile.
struct WrappedHomeCard: View {
    let year: Int
    let totalHours: Double
    /// Shown in the congratulatory line. Omitted gracefully when the user
    /// hasn't claimed a handle yet.
    var username: String? = nil
    let onOpen: () -> Void
    let onDismiss: () -> Void

    /// "2,269 hours. Great job!! logan" — falls back to just the praise
    /// when there's no handle, so it never reads as a dangling greeting.
    private var headline: String {
        let hours = "\(WrappedFormat.groupedWholeHours(totalHours)) hours."
        guard let username, !username.isEmpty else { return "\(hours) Great job!!" }
        return "\(hours) Great job!! \(username)"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR \(String(year)) WRAPPED")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(WrappedPalette.accent)

                    Text(headline)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("Tap to watch your year")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer(minLength: 8)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(WrappedPalette.accent)
            }
            .padding(AppSpacing.md)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(Color.black)
                    RadialGradient(
                        colors: [WrappedPalette.accent.opacity(0.28), .clear],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 260
                    )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(WrappedPalette.accent.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(alignment: .topTrailing) {
                // Dismiss is deliberately small and secondary — the card is
                // seasonal and self-retiring, so it shouldn't beg to be
                // closed the way a permanent banner would.
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss Wrapped")
            }
        }
        .buttonStyle(PremiumPressStyle())
    }
}

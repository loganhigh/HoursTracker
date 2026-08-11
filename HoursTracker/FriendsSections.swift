import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Friends tab sections (Phase 6)
//
// Quiet-card building blocks for the Friends hub: the friend-code card and
// the request / friend rows.
// All colors come from tokens; hairline strokes, flat fills, no glows.

// MARK: - Friend QR code

/// Renders the deep-link QR for a friend code. Scanning it with the iPhone
/// camera opens the app and pre-fills the Add a friend sheet with the code.
enum FriendQRCode {
    /// Dark modules on a white tile — QR readers need that contrast, so the
    /// tile stays white in both themes rather than adopting card colors.
    static func image(for code: String) -> UIImage? {
        guard let url = FriendsService.addFriendURL(code: code) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // The generator emits ~1pt modules; scale up so the image stays sharp
        // instead of being bilinearly blurred at display size.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// The QR block inside the friend-code card: white tile, code QR, caption.
struct FriendQRBlock: View {
    let code: String

    /// Generated once per code — CIFilter work doesn't belong in `body`.
    @State private var qrImage: UIImage?

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            if let qrImage {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(Color.white)
                    )

                Text("Scan to add me as a friend")
                    .appText(.caption)
                    .foregroundStyle(AppColors.faint)
            }
        }
        .onAppear {
            if qrImage == nil {
                qrImage = FriendQRCode.image(for: code)
            }
        }
        .onChange(of: code) { _, newCode in
            qrImage = FriendQRCode.image(for: newCode)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your friend QR code. Others can scan it with their camera to add you.")
    }
}

// MARK: - Friend code card

/// Quiet card combining the user's shareable code (tap to copy) with the
/// add-by-code field. Behavior matches the old hero card; the dress is now
/// flat card fill + hairline stroke instead of gradient + glow.
struct FriendCodeCard: View {
    let code: String?
    @Binding var codeInput: String
    let isSending: Bool
    let copyConfirmation: Bool
    let onCopy: () -> Void
    let onAdd: () -> Void
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            VStack(spacing: AppSpacing.xs) {
                Text("Your Friend Code")
                    .appText(.eyebrow)
                    .foregroundStyle(AppColors.subtext)

                Button(action: onCopy) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(code ?? "—")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColors.text)
                            .monospacedDigit()
                        Image(systemName: copyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(copyConfirmation ? AppColors.positive : AppColors.accent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(code == nil)

                // Only the transient copy confirmation shows here — the idle
                // "tap to copy" hint was removed; the code button's own
                // doc.on.doc icon already signals it's tappable.
                if copyConfirmation {
                    Text("Copied to clipboard")
                        .appText(.caption)
                        .foregroundStyle(AppColors.positive)
                }
            }

            if let code {
                FriendQRBlock(code: code)
            }

            Rectangle()
                .fill(AppColors.stroke)
                .frame(height: 1)

            addFriendRow

            Button(action: onScan) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Scan their QR code")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(AppColors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppColors.accent.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PremiumPressStyle())
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(AppColors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }

    private var addFriendRow: some View {
        HStack(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.subtext)
                TextField("Enter friend code", text: $codeInput)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(AppColors.text)
                    .onChange(of: codeInput) { _, newValue in
                        let sanitized = newValue
                            .uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                        if sanitized != newValue || sanitized.count > 8 {
                            codeInput = String(sanitized.prefix(8))
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColors.card)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 1)
                    )
            )

            Button(action: onAdd) {
                Group {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppColors.textOnAccent)
                    } else {
                        Text("Add")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textOnAccent)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(Capsule(style: .continuous).fill(AppColors.accent))
            }
            .buttonStyle(PremiumPressStyle())
            .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            .opacity(codeInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1.0)
        }
    }
}

// MARK: - Friend row

/// One friend in the Friends segment: avatar + level capsule, name and level
/// line, then weekly hours with a relative capsule bar and the streak flame.
struct FriendStatsRow: View {
    let friend: FriendProfile
    /// Highest shared `weeklyHours` among visible friends — drives the
    /// relative fill of the capsule bar. Pass 0 when nobody shares hours.
    var maxWeeklyHours: Double = 0
    var onOpenProfile: (() -> Void)? = nil
    /// Supplied by the friends list so nudging is one tap from the row that
    /// shows their hours, instead of only from the bottom of their profile.
    var onNudge: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatarView(
                    name: friend.displayName,
                    size: 48,
                    photoURL: friend.profilePhotoURL,
                    uid: friend.uid
                )
                Text("\(friend.level)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.textOnAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.accent))
                    .overlay(Capsule().stroke(AppColors.card, lineWidth: 2))
                    .offset(x: 5, y: 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                Text(friend.levelDisplayLine)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.xs)

            if friend.privacy.shareHours {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(AppTheme.Format.hours(friend.weeklyHours))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.text)
                            .monospacedDigit()
                        streakChip
                    }
                    relativeHoursBar
                    Text("this week")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.faint)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Hours hidden")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AppColors.subtext)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppColors.card))
            }

            if let onNudge {
                // Its own Button so the tap lands here rather than on the
                // row's open-profile gesture underneath.
                Button {
                    Haptics.lightTap()
                    onNudge()
                } label: {
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(AppColors.accent.opacity(0.12)))
                        .overlay(Circle().stroke(AppColors.accent.opacity(0.25), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.faint)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.lightTap()
            onOpenProfile?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens friend profile")
        // `children: .combine` folds the nudge button into the row, so VoiceOver
        // would otherwise have no way to reach it.
        .accessibilityAction(named: "Nudge") { onNudge?() }
    }

    private var streakChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppColors.streak)
            Text("\(friend.currentStreak)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.subtext)
                .monospacedDigit()
        }
    }

    /// Thin capsule showing this friend's week relative to the group max.
    private var relativeHoursBar: some View {
        let fraction: Double = maxWeeklyHours > 0
            ? min(1, max(0, friend.weeklyHours / maxWeeklyHours))
            : 0
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(AppColors.stroke.opacity(0.65))
            Capsule()
                .fill(AppColors.accent)
                .frame(width: max(4, 64 * fraction))
        }
        .frame(width: 64, height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Request row

struct FriendRequestRow: View {
    let request: FriendRequestItem
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                name: request.fromName,
                size: 44,
                photoURL: nil,
                uid: request.fromUid
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(request.fromName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                Text("Wants to be friends")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }

            Spacer()

            Button(action: onDecline) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.subtext)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(AppColors.card)
                            .overlay(Circle().stroke(AppColors.stroke, lineWidth: 1))
                    )
            }
            .buttonStyle(PremiumPressStyle())
            .accessibilityLabel("Decline request from \(request.fromName)")

            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.textOnAccent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AppColors.accent))
            }
            .buttonStyle(PremiumPressStyle())
            .accessibilityLabel("Accept request from \(request.fromName)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }
}

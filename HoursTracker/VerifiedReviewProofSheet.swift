import SwiftUI
import PhotosUI
import FirebaseFunctions
import UIKit

// MARK: - Verified mark: proof of review
//
// The mark is granted by hand, so this sheet's whole job is making the round
// trip painless: open the App Store, pick the screenshot from the library, and
// submit it. Submission goes straight to the app's own review inbox (the
// `submitVerifiedProof` callable) — no email round trip — where the admin
// console approves it and the badge appears.

struct VerifiedReviewProofSheet: View {
    /// Already verified — the sheet congratulates instead of collecting.
    let isVerified: Bool
    let accountName: String
    let accountUid: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pickerItem: PhotosPickerItem?
    @State private var stage: Stage = .idle
    @State private var isSubmitting = false

    private let functions = Functions.functions(region: "us-central1")

    /// Where the flow is, which is also what the action area renders.
    private enum Stage: Equatable {
        case idle
        /// Pulling the picked asset out of the photo library.
        case loading
        case ready(UIImage)
        case sent
        case failed(String)

        var image: UIImage? {
            if case let .ready(image) = self { return image }
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    header

                    if isVerified {
                        alreadyVerified
                    } else {
                        steps
                        actionArea
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.lg)
                .frame(maxWidth: .infinity)
            }
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Verified Mark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadScreenshot(item) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: AppSpacing.sm) {
            VerifiedBadgeView(variant: .shimmer, size: 52)
                .shadow(color: Color(red: 0.114, green: 0.631, blue: 0.949).opacity(0.35), radius: 14)

            Text(isVerified ? "You're verified" : "Get the verified mark")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColors.text)

            Text(isVerified
                 ? "Your mark shows beside your name everywhere other trackers can see you."
                 : "Leave a review, submit a screenshot of it, and we'll add the mark beside your name.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.subtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var alreadyVerified: some View {
        Text("Nothing left to do — thanks for reviewing.")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(AppColors.subtext)
            .padding(.top, AppSpacing.xs)
    }

    // MARK: Steps

    private var steps: some View {
        VStack(spacing: AppSpacing.sm) {
            stepRow(
                number: 1,
                title: "Write your review",
                detail: "Opens the App Store review page.",
                isDone: false
            ) {
                Button {
                    Haptics.lightTap()
                    AppActions.openAppStoreListing()
                } label: {
                    Text("Open")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textOnAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule(style: .continuous).fill(AppColors.accent))
                }
                .buttonStyle(.plain)
            }

            stepRow(
                number: 2,
                title: "Screenshot it",
                detail: "Side button + volume up.",
                isDone: false
            ) { EmptyView() }

            stepRow(
                number: 3,
                title: "Send us a screenshot!",
                detail: "Submitted right here in the app.",
                isDone: stage == .sent
            ) { EmptyView() }
        }
    }

    private func stepRow<Trailing: View>(
        number: Int,
        title: String,
        detail: String,
        isDone: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(isDone ? AppColors.accent : AppColors.accent.opacity(0.14))
                    .frame(width: 28, height: 28)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(AppColors.textOnAccent)
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColors.accent)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            trailing()
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 0.5)
                )
        )
    }

    // MARK: Action area

    @ViewBuilder
    private var actionArea: some View {
        switch stage {
        case .idle:
            picker(label: "Choose screenshot", icon: "photo.on.rectangle.angled")

        case .loading:
            LoadingScreenshotCard()
                .transition(.opacity)

        case let .ready(image):
            VStack(spacing: AppSpacing.sm) {
                ScreenshotPreview(image: image)
                sendButton
                picker(label: "Pick a different one", icon: "arrow.triangle.2.circlepath")
                    .opacity(0.8)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))

        case .sent:
            SentConfirmation()
                .transition(.opacity.combined(with: .scale(scale: 0.94)))

        case let .failed(message):
            VStack(spacing: AppSpacing.sm) {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.negative)
                    .multilineTextAlignment(.center)
                if stage.image != nil { sendButton }
                picker(label: "Choose screenshot", icon: "photo.on.rectangle.angled")
            }
        }
    }

    private func picker(label: String, icon: String) -> some View {
        // Deliberately all images, not `.screenshots`: that filter is strict,
        // and proof that arrived any other way (AirDropped from another device,
        // cropped, re-saved) would silently not appear in the picker.
        PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColors.accent.opacity(0.35), lineWidth: 1)
                    )
            )
        }
    }

    private var sendButton: some View {
        Button {
            Haptics.lightTap()
            Task { await submitProof() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .tint(AppColors.textOnAccent)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .bold))
                }
                Text(isSubmitting ? "Submitting…" : "Submit for review")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(AppColors.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.accent.opacity(isSubmitting ? 0.7 : 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    /// Ships the screenshot to the app's own review inbox. The image is
    /// re-encoded at 1024px JPEG first, so the call carries a few hundred
    /// kilobytes instead of a full-resolution screenshot.
    private func submitProof() async {
        guard let image = stage.image, !isSubmitting else { return }
        guard accountUid != nil else {
            stage = .failed("Sign in to submit — the mark is attached to your account.")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        guard let data = Self.encodedJPEG(image) else {
            stage = .failed("That image couldn't be read. Try picking it again.")
            return
        }
        do {
            _ = try await functions.httpsCallable("submitVerifiedProof")
                .call(["photoBase64": data.base64EncodedString()])
            Haptics.success()
            withAnimation(AppMotion.animation(AppMotion.Spring.celebratory, reduceMotion: reduceMotion)) {
                stage = .sent
            }
        } catch {
            Haptics.error()
            withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                stage = .failed("Couldn't submit right now. Check your connection and try again.")
            }
        }
    }

    /// Longest edge 1024px — enough to read a review screenshot comfortably.
    private static func encodedJPEG(_ image: UIImage, maxEdge: CGFloat = 1024) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxEdge / longest)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    // MARK: Loading

    /// Photo-library transfers are usually instant for a local screenshot but
    /// can stall on an iCloud download, so this always shows rather than
    /// flickering only on slow ones.
    private func loadScreenshot(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            stage = .loading
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            Haptics.error()
            withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                stage = .failed("That image couldn't be read. Try picking it again.")
            }
            return
        }
        Haptics.lightTap()
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            stage = .ready(image)
        }
    }
}

// MARK: - Loading card

/// A shimmering placeholder in the shape of the preview it's about to become,
/// so the layout doesn't jump when the real screenshot lands.
private struct LoadingScreenshotCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 190

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .fill(AppColors.card.opacity(0.55))
            .frame(height: height)
            .overlay { shimmer }
            .overlay {
                VStack(spacing: AppSpacing.xs) {
                    ProgressView()
                        .tint(AppColors.accent)
                    Text("Preparing your screenshot…")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.subtext)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
            .accessibilityLabel("Loading screenshot")
    }

    @ViewBuilder
    private var shimmer: some View {
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                let cycle = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.6) / 1.6
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, AppColors.text.opacity(0.07), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: -geo.size.width * 0.45 + geo.size.width * 1.45 * cycle)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Preview of the picked shot

private struct ScreenshotPreview: View {
    let image: UIImage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        // Color.clear sets the size and the photo rides on top: an overlay
        // never grows its parent, so a tall screenshot can't stretch the sheet.
        Color.clear
            .frame(height: 190)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .background(Circle().fill(AppColors.bg))
                    .padding(8)
                    .scaleEffect(appeared ? 1 : 0.2)
                    .opacity(appeared ? 1 : 0)
            }
            .onAppear {
                withAnimation(AppMotion.animation(AppMotion.Spring.celebratory, reduceMotion: reduceMotion).delay(0.08)) {
                    appeared = true
                }
            }
    }
}

// MARK: - Sent

/// The badge pops in and pulses once. Deliberately does NOT claim the mark is
/// live — it's granted by hand after the screenshot is read.
private struct SentConfirmation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            VerifiedBadgeView(variant: .shimmer, size: 44)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)

            Text("Sent!")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColors.text)

            Text("Your screenshot is in our review queue. Once it's approved the mark shows up on its own — no need to check back.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.subtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.accent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(AppMotion.animation(AppMotion.Spring.celebratory, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }
}

import SwiftUI
import PhotosUI
import MessageUI
import UIKit

// MARK: - Verified mark: proof of review
//
// The mark is granted by hand, so this sheet's whole job is making the round
// trip painless: open the App Store, pick the screenshot from the library, and
// hand off a pre-addressed, pre-filled email with the shot attached. The user
// still taps Send themselves — that's Mail's own composer, not ours.
//
// The email carries the account's uid and name in its body. Without them a
// screenshot of an App Store review (which carries only a nickname) can't be
// matched back to an account, and the grant would be guesswork.

struct VerifiedReviewProofSheet: View {
    /// Already verified — the sheet congratulates instead of collecting.
    let isVerified: Bool
    let accountName: String
    let accountUid: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pickerItem: PhotosPickerItem?
    @State private var stage: Stage = .idle
    @State private var showingMailComposer = false
    @State private var showingShareSheet = false
    @State private var copiedAddress = false

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

    private var emailSubject: String {
        "Hour Tracker — verified mark request"
    }

    /// Everything needed to match the review to an account, so the grant isn't
    /// a guess against an App Store nickname.
    private var emailBody: String {
        """
        Hi! I left a review for Hour Tracker — screenshot attached.

        Name: \(accountName.isEmpty ? "(not set)" : accountName)
        Account ID: \(accountUid ?? "(signed out)")
        App version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))

        Thanks!
        """
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
        .sheet(isPresented: $showingMailComposer) {
            MailComposeView(
                recipient: VerifiedTracker.proofRecipient,
                subject: emailSubject,
                body: emailBody,
                attachment: stage.image
            ) { result in
                showingMailComposer = false
                switch result {
                case .sent:
                    Haptics.success()
                    withAnimation(AppMotion.animation(.spring(response: 0.5, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
                        stage = .sent
                    }
                case .failed:
                    Haptics.error()
                    stage = .failed("Mail couldn't send that. Try the share sheet instead.")
                default:
                    break // Cancelled or saved as a draft: leave the shot staged.
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingShareSheet) {
            // No Mail account on the device. The share sheet reaches Gmail,
            // Outlook, or whatever else they actually use — but it can't
            // pre-address the message, so the address goes on the clipboard
            // on the way in (see sendButton).
            ProofShareSheet(items: shareItems) { completed in
                showingShareSheet = false
                guard completed else { return }
                Haptics.success()
                withAnimation(AppMotion.animation(AppMotion.Spring.celebratory, reduceMotion: reduceMotion)) {
                    stage = .sent
                }
            }
        }
    }

    private var shareItems: [Any] {
        var items: [Any] = ["\(emailSubject)\n\n\(emailBody)"]
        if let image = stage.image { items.append(image) }
        return items
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
                 : "Leave a review, send us a screenshot of it, and we'll add the mark beside your name.")
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
                detail: VerifiedTracker.proofRecipient,
                isDone: stage == .sent
            ) {
                Button {
                    UIPasteboard.general.string = VerifiedTracker.proofRecipient
                    Haptics.lightTap()
                    withAnimation(.snappy) { copiedAddress = true }
                } label: {
                    Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(copiedAddress ? AppColors.accent : AppColors.subtext)
                        .frame(width: 30, height: 30)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy email address")
            }
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
            if MFMailComposeViewController.canSendMail() {
                showingMailComposer = true
            } else {
                // Nothing downstream can fill in the recipient for them.
                UIPasteboard.general.string = VerifiedTracker.proofRecipient
                copiedAddress = true
                showingShareSheet = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("Email it to us")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(AppColors.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.accent)
            )
        }
        .buttonStyle(.plain)
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

            Text("We'll add your mark once we've had a look. It shows up on its own — no need to check back.")
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

// MARK: - Share fallback

/// Like `ShareSheet`, but reports whether the user actually completed a share
/// rather than just dismissing — the difference between "sent" and "changed
/// their mind", which the confirmation below shouldn't get wrong.
private struct ProofShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in onComplete(completed) }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Mail composer

/// Wraps MFMailComposeViewController. The user sends it themselves — this only
/// pre-fills the recipient, subject, body, and attachment.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let attachment: UIImage?
    var onFinish: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let attachment, let data = attachment.jpegData(compressionQuality: 0.85) {
            vc.addAttachmentData(data, mimeType: "image/jpeg", fileName: "review.jpg")
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) { [onFinish] in
                onFinish(error == nil ? result : .failed)
            }
        }
    }
}

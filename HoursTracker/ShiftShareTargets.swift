import SwiftUI
import UIKit
import MessageUI
import LinkPresentation
import Photos

// MARK: - Share targets for the shift earnings card
//
// Three first-class destinations plus Save Image:
//   - Messages: the in-app composer with the card attached.
//   - WhatsApp: hands the image straight to WhatsApp via its documented
//     `net.whatsapp.image` document type.
//   - Snapchat: direct sharing needs Snap's Creative Kit SDK and client ID,
//     so for now it opens the share sheet, where Snapchat appears when
//     installed.
//   - Save Image: straight to Photos (add-only permission).
// Anything that can't go direct (app not installed, no attachments allowed)
// falls back to a trimmed system share sheet rather than failing silently.

enum ShiftShareTarget: String, CaseIterable, Identifiable {
    case messages, whatsapp, snapchat, save

    var id: String { rawValue }

    var label: String {
        switch self {
        case .messages: return "Messages"
        case .whatsapp: return "WhatsApp"
        case .snapchat: return "Snapchat"
        case .save: return "Save Image"
        }
    }

    /// Brand artwork from the asset catalog; nil → drawn from an SF Symbol.
    var brandAsset: String? {
        switch self {
        case .whatsapp: return "BrandWhatsApp"
        case .snapchat: return "BrandSnapchat"
        case .messages, .save: return nil
        }
    }

    var symbol: String {
        switch self {
        case .messages: return "message.fill"
        case .save: return "square.and.arrow.down"
        default: return "questionmark"
        }
    }

    var symbolBackground: Color {
        switch self {
        case .messages: return Color(hex: 0x34C759)
        default: return Color.white.opacity(0.18)
        }
    }
}

@MainActor
enum ShiftSharer {
    /// Kept alive while presented — both are released by UIKit otherwise.
    private static var documentController: UIDocumentInteractionController?
    private static let messageDelegate = MessageComposeDelegate()

    static func share(_ image: UIImage, to target: ShiftShareTarget) {
        guard let png = image.pngData() else { return }
        switch target {
        case .messages:
            guard MFMessageComposeViewController.canSendText(),
                  MFMessageComposeViewController.canSendAttachments() else {
                return presentShareSheet(image)
            }
            let composer = MFMessageComposeViewController()
            composer.messageComposeDelegate = messageDelegate
            composer.addAttachmentData(png, typeIdentifier: "public.png", filename: "my-shift.png")
            present(composer)

        case .whatsapp:
            guard let url = URL(string: "whatsapp://"), UIApplication.shared.canOpenURL(url) else {
                return presentShareSheet(image)
            }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("my-shift.wai")
            do { try png.write(to: file, options: .atomic) } catch { return presentShareSheet(image) }
            let controller = UIDocumentInteractionController(url: file)
            controller.uti = "net.whatsapp.image"
            documentController = controller
            guard let host = topViewController(),
                  controller.presentOpenInMenu(from: host.view.bounds, in: host.view, animated: true) else {
                return presentShareSheet(image)
            }

        case .snapchat:
            presentShareSheet(image)

        case .save:
            break // handled by save(_:) so the button can show the result
        }
    }

    /// Saves to Photos with add-only access. true on success.
    static func save(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            return false
        }
    }

    /// The system sheet, minus the destinations that make no sense for a
    /// photo of a shift (contacts, printing, reading list, reminders…).
    static func presentShareSheet(_ image: UIImage) {
        let sheet = UIActivityViewController(activityItems: [ShareImageItem(image: image)], applicationActivities: nil)
        sheet.excludedActivityTypes = [
            .assignToContact, .addToReadingList, .print, .markupAsPDF, .openInIBooks,
            UIActivity.ActivityType("com.apple.reminders.sharingextension"),
            UIActivity.ActivityType("com.apple.mobilenotes.SharingExtension"),
        ]
        present(sheet)
    }

    private static func present(_ controller: UIViewController) {
        guard let host = topViewController() else { return }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.maxY, width: 0, height: 0)
        }
        host.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Gives the share sheet a real thumbnail and title for the card instead of
/// a blank placeholder icon.
private final class ShareImageItem: NSObject, UIActivityItemSource {
    let image: UIImage
    init(image: UIImage) { self.image = image }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { image }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { image }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "My shift"
        metadata.imageProvider = NSItemProvider(object: image)
        metadata.iconProvider = NSItemProvider(object: image)
        return metadata
    }
}

private final class MessageComposeDelegate: NSObject, MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                      didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
}

/// The row of share buttons under the card.
struct ShiftShareRow: View {
    let image: UIImage?

    private enum SaveState { case idle, saving, saved, failed }
    @State private var saveState: SaveState = .idle

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ShiftShareTarget.allCases) { target in
                Button {
                    guard let image else { return }
                    Haptics.lightTap()
                    if target == .save {
                        saveState = .saving
                        Task {
                            let ok = await ShiftSharer.save(image)
                            saveState = ok ? .saved : .failed
                            if ok { Haptics.success() } else { Haptics.error() }
                            // Confirm, then return to "Save Image" so the
                            // button never looks permanently done.
                            try? await Task.sleep(nanoseconds: ok ? 1_800_000_000 : 3_000_000_000)
                            withAnimation(.easeInOut(duration: 0.25)) { saveState = .idle }
                        }
                    } else {
                        ShiftSharer.share(image, to: target)
                    }
                } label: {
                    VStack(spacing: 6) {
                        icon(for: target)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                        Text(label(for: target))
                            .contentTransition(.opacity)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(image == nil || (target == .save && saveState == .saving))
                .accessibilityLabel(target == .save ? label(for: target) : "Share to \(target.label)")
            }
        }
    }

    @ViewBuilder
    private func icon(for target: ShiftShareTarget) -> some View {
        if let asset = target.brandAsset {
            Image(asset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            ZStack {
                target.symbolBackground
                Image(systemName: target == .save ? saveSymbol : target.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    private var saveSymbol: String {
        switch saveState {
        case .saved: return "checkmark"
        case .failed: return "exclamationmark"
        default: return "square.and.arrow.down"
        }
    }

    private func label(for target: ShiftShareTarget) -> String {
        guard target == .save else { return target.label }
        switch saveState {
        case .saving: return "Saving…"
        case .saved: return "Saved"
        case .failed: return "Allow in Settings"
        case .idle: return "Save Image"
        }
    }
}

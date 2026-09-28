import SwiftUI
import UIKit
import MessageUI
import LinkPresentation

// MARK: - Share targets for the shift earnings card
//
// Four first-class destinations plus a "More" sheet:
//   - Messages: the in-app composer with the card attached.
//   - WhatsApp: hands the image straight to WhatsApp via its documented
//     `net.whatsapp.image` document type.
//   - Instagram: posts to Stories through Instagram's official URL scheme.
//     Meta requires a registered Facebook App ID for this; until one is set
//     in `ShareConfig.metaAppID`, the button opens the share sheet instead,
//     where Instagram appears when it's installed.
//   - Snapchat: direct sharing needs Snap's Creative Kit SDK and client ID,
//     so for now it opens the share sheet, where Snapchat appears when
//     installed.
// Anything that can't go direct (app not installed, no attachments allowed)
// falls back to the same trimmed share sheet rather than failing silently.

enum ShareConfig {
    /// Facebook App ID from developers.facebook.com, required by Instagram
    /// for direct Stories sharing. nil → Instagram uses the share sheet.
    static let metaAppID: String? = nil
}

enum ShiftShareTarget: String, CaseIterable, Identifiable {
    case messages, whatsapp, instagram, snapchat, more

    var id: String { rawValue }

    var label: String {
        switch self {
        case .messages: return "Messages"
        case .whatsapp: return "WhatsApp"
        case .instagram: return "Instagram"
        case .snapchat: return "Snapchat"
        case .more: return "More"
        }
    }

    var symbol: String {
        switch self {
        case .messages: return "message.fill"
        case .whatsapp: return "phone.fill"
        case .instagram: return "camera"
        case .snapchat: return "bolt.fill"
        case .more: return "ellipsis"
        }
    }

    var glyphColor: Color {
        switch self {
        case .snapchat: return .black
        default: return .white
        }
    }

    @ViewBuilder var background: some View {
        switch self {
        case .messages: Color(hex: 0x34C759)
        case .whatsapp: Color(hex: 0x25D366)
        case .instagram:
            LinearGradient(
                colors: [Color(hex: 0xFEDA75), Color(hex: 0xFA7E1E), Color(hex: 0xD62976), Color(hex: 0x962FBF), Color(hex: 0x4F5BD5)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .snapchat: Color(hex: 0xFFFC00)
        case .more: Color.white.opacity(0.18)
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

        case .instagram:
            guard let appID = ShareConfig.metaAppID,
                  let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
                  UIApplication.shared.canOpenURL(url) else {
                return presentShareSheet(image)
            }
            UIPasteboard.general.setItems(
                [["com.instagram.sharedSticker.backgroundImage": png]],
                options: [.expirationDate: Date().addingTimeInterval(300)]
            )
            UIApplication.shared.open(url)

        case .snapchat, .more:
            presentShareSheet(image)
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ShiftShareTarget.allCases) { target in
                Button {
                    Haptics.lightTap()
                    if let image { ShiftSharer.share(image, to: target) }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            target.background
                            Image(systemName: target.symbol)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(target.glyphColor)
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        Text(target.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(image == nil)
                .accessibilityLabel("Share to \(target.label)")
            }
        }
    }
}

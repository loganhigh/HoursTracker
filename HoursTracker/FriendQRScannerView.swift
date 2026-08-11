import SwiftUI
import AVFoundation

// MARK: - Friend QR scanner
//
// In-app camera for scanning another user's friend QR. Accepts the same
// `<scheme>://add-friend?code=XXXXXX` deep link the codes encode, and also a
// bare friend code, so a code shared as plain text still scans. Reports the
// code back to the caller, which fills the Add a friend field with it —
// scanning never sends a request on its own.

struct FriendQRScannerView: View {
    var onCancel: () -> Void
    var onScan: (String) -> Void

    @State private var permission: PermissionState = .checking
    /// Latches on the first accepted code so a continuously-scanning session
    /// can't fire the callback dozens of times for one QR.
    @State private var hasScanned = false

    private enum PermissionState {
        case checking, granted, denied
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch permission {
                case .checking:
                    ProgressView()
                        .tint(.white)
                case .granted:
                    scanner
                case .denied:
                    deniedState
                }
            }
            .navigationTitle("Scan a friend code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
        .task { await resolvePermission() }
    }

    private var scanner: some View {
        ZStack {
            QRCameraPreview { payload in
                guard !hasScanned, let code = Self.friendCode(from: payload) else { return }
                hasScanned = true
                Haptics.success()
                onScan(code)
            }
            .ignoresSafeArea()

            // Viewfinder — a plain framing aid, no dimming, so the user can
            // see enough of the scene to aim.
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 240, height: 240)

            VStack {
                Spacer()
                Text("Point the camera at their friend QR code")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.xxl)
            }
        }
    }

    private var deniedState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            Text("Camera access is off")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Turn on camera access for Hour Tracker to scan a friend's QR code. You can still add them by typing their code.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .fontWeight(.semibold)
            .foregroundStyle(AppColors.accent)
            .padding(.top, AppSpacing.xxs)
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private func resolvePermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .granted
        case .notDetermined:
            permission = await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default:
            permission = .denied
        }
    }

    /// Pulls a friend code out of a scanned payload: either the deep link the
    /// app's own QR encodes, or a bare code someone shared as text.
    static func friendCode(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           url.host == "add-friend",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            return code.uppercased()
        }

        // Bare code fallback — same shape the entry field accepts.
        let bare = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        guard bare.count >= 4, bare.count <= 8, bare == trimmed.uppercased() else { return nil }
        return bare
    }
}

// MARK: - Camera preview

/// AVCaptureSession wrapper that reports decoded QR payloads. The session runs
/// on its own queue and is torn down when the view goes away, so no camera
/// stays live behind a dismissed sheet.
private struct QRCameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {
        uiViewController.onCode = onCode
    }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "friend-qr-scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // Assigned only after the output is attached to a session — setting
        // it earlier throws, because the supported types aren't known yet.
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        onCode?(value)
    }
}

import SwiftUI
import AVFoundation
import Combine

// MARK: - Cinematic asset catalog
//
// One standard level-up cinematic and one prestige cinematic, generated
// against the app's near-black background. The catalog is keyed so
// tier-specific variants can be added later (drop `cinematic_level_up_gold.mp4`
// into the bundle and add a case) without touching the player or the
// celebration flow — every lookup falls back to the standard asset.

enum CelebrationCinematic {
    case levelUp(tier: PrestigeTheme.Tier)
    case prestige(tier: PrestigeTheme.Tier)

    /// Playback rate applied to the source clip. The generated clips are 4s
    /// (the model's minimum); level-up plays at 2× for a ~2s beat, prestige at
    /// 1.4× for a more deliberate ~2.9s.
    var playbackRate: Float {
        switch self {
        case .levelUp: return 2.0
        case .prestige: return 1.4
        }
    }

    /// Resource names tried in order; first present in the bundle wins.
    private var candidates: [String] {
        switch self {
        case .levelUp(let tier):
            return ["cinematic_level_up_\(tier.assetSuffix)", "cinematic_level_up_standard"]
        case .prestige(let tier):
            return ["cinematic_prestige_\(tier.assetSuffix)", "cinematic_prestige_standard"]
        }
    }

    var url: URL? {
        candidates.lazy.compactMap {
            Bundle.main.url(forResource: $0, withExtension: "mp4")
        }.first
    }
}

extension PrestigeTheme.Tier {
    /// "silver", "gold", … — lowercased tier name for asset lookups.
    var assetSuffix: String { name.lowercased() }
}

// MARK: - Preloading player model

/// Owns the AVPlayer for one celebration. Created shortly before presentation
/// so the asset is warm when the cinematic stage starts, and discarded with
/// the celebration so no video stays resident afterwards.
@MainActor
final class LevelAnimationPlayer: ObservableObject {
    @Published private(set) var isReady = false
    /// Flips true when playback finishes (or was never possible, so the
    /// celebration can skip the cinematic stage rather than hang).
    @Published private(set) var didFinish = false

    let player = AVPlayer()
    private let cinematic: CelebrationCinematic
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?

    /// True when the bundle actually contains a clip for this cinematic.
    let hasAsset: Bool

    init(cinematic: CelebrationCinematic) {
        self.cinematic = cinematic
        self.hasAsset = cinematic.url != nil
        player.isMuted = true
        player.actionAtItemEnd = .pause
        guard let url = cinematic.url else { return }

        // AVURLAsset loads off the main thread; replaceCurrentItem with a
        // not-yet-ready item is cheap and status is observed for readiness.
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        player.replaceCurrentItem(with: item)

        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .readyToPlay {
                    self.isReady = true
                } else if item.status == .failed {
                    // Treat an undecodable asset like a missing one.
                    self.didFinish = true
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.didFinish = true
            }
        }
    }

    func play() {
        guard hasAsset, !didFinish else {
            didFinish = true
            return
        }
        player.rate = cinematic.playbackRate
    }

    func teardown() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

// MARK: - Chrome-less video surface

/// AVPlayerLayer host — no controls, no letterboxing chrome. The layer
/// aspect-fills so the 9:16 clip covers its frame edge to edge.
struct CinematicVideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

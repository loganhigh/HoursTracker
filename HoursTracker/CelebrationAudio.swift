import AVFoundation

// MARK: - Celebration audio
//
// Sound hooks for the level-up and prestige celebrations. Each event looks for
// a dedicated file first (`level_up.wav` / `prestige.wav`) and falls back
// through the formats below to the bundled `level_up.caf`, so dropping better
// sounds into the project later upgrades the experience with no code change —
// and a missing file plays nothing rather than breaking.

@MainActor
final class CelebrationAudio {
    static let shared = CelebrationAudio()

    enum Event {
        case levelUp
        case prestige

        /// Resource names tried in order; first hit wins.
        var candidates: [(name: String, ext: String)] {
            switch self {
            case .levelUp:
                return [("level_up", "wav"), ("level_up", "caf"), ("level_up", "m4a")]
            case .prestige:
                return [("prestige", "wav"), ("prestige", "caf"), ("prestige", "m4a"),
                        ("level_up", "caf")]
            }
        }
    }

    /// Kept alive for the duration of playback; replaced on the next play.
    private var player: AVAudioPlayer?

    private init() {}

    func play(_ event: Event) {
        guard let url = event.candidates.lazy.compactMap({
            Bundle.main.url(forResource: $0.name, withExtension: $0.ext)
        }).first else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 1.0
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

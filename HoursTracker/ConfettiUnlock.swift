import SwiftUI
import Combine

// Stores which badge names were already celebrated, so you only see it once.
final class BadgeUnlockTracker: ObservableObject {
    @AppStorage("celebrated_badges_v1") private var celebratedCSV: String = ""

    func hasCelebrated(_ key: String) -> Bool {
        celebratedSet.contains(key)
    }

    func markCelebrated(_ key: String) {
        var s = celebratedSet
        s.insert(key)
        celebratedCSV = s.sorted().joined(separator: "|")
    }

    private var celebratedSet: Set<String> {
        Set(celebratedCSV.split(separator: "|").map(String.init))
    }
}

struct ConfettiUnlockSheet: View {
    let title: String
    let subtitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    var body: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                BadgeGlowHero(systemImage: "sparkles")

                Text(title)
                    .font(AppTheme.Typography.h1)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(AppTheme.Typography.sub)
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                PrimaryButton("Nice 😎", systemImage: "checkmark.circle.fill") {
                    dismiss()
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)

                Spacer()
            }

            if !reduceMotion {
                ConfettiLayer(active: burst)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            Haptics.success()
            if !reduceMotion {
                withAnimation(AppMotion.Spring.smooth) {
                    burst = true
                }
            }
        }
    }
}

struct BadgeUnlockCelebrationSheet: View {
    let badgeName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    var body: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                BadgeGlowHero(systemImage: "medal.fill")

                Text("Badge Unlocked")
                    .font(AppTheme.Typography.h1)
                    .multilineTextAlignment(.center)

                Text(badgeName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.accent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                Text("New achievement added to your collection.")
                    .font(AppTheme.Typography.sub)
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                PrimaryButton("Continue", systemImage: "arrow.right.circle.fill") {
                    dismiss()
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)

                Spacer()
            }

            if !reduceMotion {
                ConfettiLayer(active: burst)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            Haptics.success()
            if !reduceMotion {
                withAnimation(AppMotion.Spring.smooth) {
                    burst = true
                }
            }
        }
    }
}

struct ConfettiLayer: View {
    let active: Bool
    var palette: [Color]? = nil
    var pieceCount: Int = 42

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [ConfettiPiece] = []

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geo in
                ZStack {
                    ForEach(pieces) { p in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(p.color)
                            .frame(width: p.size, height: p.size * 2.2)
                            .rotationEffect(.degrees(active ? p.spin : 0))
                            .position(
                                x: active ? p.endX * geo.size.width : p.startX * geo.size.width,
                                y: active ? geo.size.height + 40 : -40
                            )
                            .opacity(active ? 0.0 : 1.0)
                            .animation(.easeOut(duration: p.duration).delay(p.delay), value: active)
                    }
                }
            }
            .onAppear {
                pieces = (0..<pieceCount).map { _ in ConfettiPiece.random(palette: palette) }
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let startX: CGFloat
    let endX: CGFloat
    let spin: Double
    let size: CGFloat
    let duration: Double
    let delay: Double
    let color: Color

    static func random(palette: [Color]? = nil) -> ConfettiPiece {
        let defaultPalette: [Color] = [
            .green, .blue, .purple, .yellow, .orange, .pink, .mint, .teal
        ]
        let colors = palette ?? defaultPalette
        return ConfettiPiece(
            startX: CGFloat.random(in: 0.05...0.95),
            endX: CGFloat.random(in: 0.05...0.95),
            spin: Double.random(in: 120...920),
            size: CGFloat.random(in: 6...12),
            duration: Double.random(in: 1.2...2.2),
            delay: Double.random(in: 0.0...0.25),
            color: (colors.randomElement() ?? .purple).opacity(0.95)
        )
    }
}

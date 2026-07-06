import SwiftUI

private let toastAutoDismissSeconds: Double = 1.35

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    var message: String
    var showsCheckmark: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checkScale: CGFloat = 0.6

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content

            if isPresented {
                HStack(spacing: 10) {
                    if showsCheckmark {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.success)
                            .scaleEffect(checkScale)
                    }
                    Text(message)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .move(edge: .bottom))
                    )
                )
                .zIndex(1)
                .onAppear {
                    if showsCheckmark {
                        if reduceMotion {
                            checkScale = 1
                        } else {
                            withAnimation(AppMotion.Spring.celebratory) {
                                checkScale = 1
                            }
                        }
                    }
                }
            }
        }
        .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: isPresented)
        .onChange(of: isPresented) { _, newValue in
            guard newValue else { return }
            if showsCheckmark { Haptics.success() }
            DispatchQueue.main.asyncAfter(deadline: .now() + toastAutoDismissSeconds) {
                isPresented = false
            }
        }
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, showsCheckmark: Bool = false) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, showsCheckmark: showsCheckmark))
    }
}

import SwiftUI
import AuthenticationServices

/// Themed Sign in with Apple control wired to `AuthService`.
struct SignInWithAppleButtonView: View {
    @EnvironmentObject private var authService: AuthService
    var height: CGFloat = 50

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            authService.prepareAppleSignInRequest(request)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                Task { await authService.handleAppleAuthorization(authorization) }
            case .failure(let error):
                authService.lastError = error.localizedDescription
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .disabled(authService.isSigningIn)
        .opacity(authService.isSigningIn ? 0.6 : 1)
    }
}

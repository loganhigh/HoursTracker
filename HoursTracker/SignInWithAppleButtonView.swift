import SwiftUI
import AuthenticationServices

/// Themed Sign in with Apple control wired to `AuthService`.
struct SignInWithAppleButtonView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat = 50

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            authService.prepareAppleSignInRequest(request)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                Task { await authService.handleAppleAuthorization(authorization) }
            case .failure(let error):
                // Cancelling the sheet is not a failure — Google's path already
                // stays silent on cancel; this one showed a raw "error 1001".
                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                    return
                }
                authService.lastError = error.localizedDescription
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .disabled(authService.isSigningIn)
        .opacity(authService.isSigningIn ? 0.6 : 1)
    }
}

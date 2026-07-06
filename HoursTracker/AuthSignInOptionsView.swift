import SwiftUI

/// Apple, Google, and email/password sign-in — used in onboarding and Account.
struct AuthSignInOptionsView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        VStack(spacing: 14) {
            SignInWithAppleButtonView()

            googleButton

            orDivider

            emailSection

            if let err = authService.lastError {
                Text(err)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.danger)
                    .multilineTextAlignment(.center)
            }

            if authService.isSignedIn {
                signedInBanner
            }
        }
    }

    private var googleButton: some View {
        Button {
            Haptics.lightTap()
            Task { await authService.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                Image("GoogleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.Colors.card2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(authService.isSigningIn)
        .opacity(authService.isSigningIn ? 0.6 : 1)
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppTheme.Colors.stroke)
                .frame(height: 1)
            Text("or use email")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)
            Rectangle()
                .fill(AppTheme.Colors.stroke)
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private var emailSection: some View {
        VStack(spacing: 10) {
            Picker("Account mode", selection: $isCreatingAccount) {
                Text("Sign in").tag(false)
                Text("Create account").tag(true)
            }
            .pickerStyle(.segmented)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .authFieldStyle()

            SecureField("Password", text: $password)
                .textContentType(isCreatingAccount ? .newPassword : .password)
                .focused($focusedField, equals: .password)
                .authFieldStyle()

            Button {
                Haptics.lightTap()
                focusedField = nil
                Task {
                    await authService.signInWithEmail(
                        email: email,
                        password: password,
                        createAccount: isCreatingAccount
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    if authService.isSigningIn {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(isCreatingAccount ? "Create account" : "Sign in with email")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canSubmitEmail ? AppTheme.Colors.accentGradient : LinearGradient(colors: [AppTheme.Colors.stroke, AppTheme.Colors.stroke], startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(PremiumPressStyle())
            .disabled(!canSubmitEmail || authService.isSigningIn)
        }
    }

    private var signedInBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
            Text("Signed in — you're all set!")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
        }
        .padding(.top, 4)
    }

    private var canSubmitEmail: Bool {
        email.contains("@") && password.count >= 6
    }
}

private extension View {
    func authFieldStyle() -> some View {
        font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.Colors.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.Colors.card2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                    )
            )
            .tint(AppTheme.Colors.accent)
    }
}

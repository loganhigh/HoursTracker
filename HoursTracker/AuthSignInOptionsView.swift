import SwiftUI

/// Apple, Google, and email/password sign-in — used in onboarding and Account.
///
/// Laid out after the supplied SignInForm: labelled email and password fields
/// with a leading glyph inside the field, a forgot-password affordance, the
/// primary submit, then the social providers, then a sign-in/sign-up switch at
/// the foot. Both social buttons sit on white so they read as the vendors'
/// own marks rather than as app chrome.
struct AuthSignInOptionsView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var resetConfirmation: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            emailField
            passwordField

            if !isCreatingAccount {
                forgotPasswordRow
            }

            submitButton

            orDivider

            SignInWithAppleButtonView()
            googleButton

            accountSwitch

            if let resetConfirmation {
                Text(resetConfirmation)
                    .appText(.caption)
                    .foregroundStyle(AppColors.positive)
                    .multilineTextAlignment(.center)
            }

            if let err = authService.lastError {
                Text(err)
                    .appText(.caption)
                    .foregroundStyle(AppColors.negative)
                    .multilineTextAlignment(.center)
            }

            if authService.isSignedIn {
                signedInBanner
            }
        }
    }

    // MARK: Fields

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Email")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(AppColors.subtext)

            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.faint)
                TextField("Enter your email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
            }
            .authFieldChrome(focused: focusedField == .email)
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(AppColors.subtext)

            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.faint)
                SecureField("Enter your password", text: $password)
                    .textContentType(isCreatingAccount ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
            }
            .authFieldChrome(focused: focusedField == .password)
        }
    }

    /// The reference pairs this with a "Remember me" checkbox. That control is
    /// deliberately absent: Firebase persists the session to the keychain
    /// regardless, so the checkbox could only ever be decorative.
    private var forgotPasswordRow: some View {
        HStack {
            Spacer()
            Button("Forgot password?") {
                Haptics.lightTap()
                focusedField = nil
                resetConfirmation = nil
                Task {
                    await authService.sendPasswordReset(email: email)
                    if authService.lastError == nil {
                        resetConfirmation = "Password reset sent — check your email."
                    }
                }
            }
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(AppColors.accent)
            .disabled(email.isEmpty || authService.isSigningIn)
            .opacity(email.isEmpty ? 0.5 : 1)
        }
    }

    // MARK: Actions

    private var submitButton: some View {
        Button {
            Haptics.lightTap()
            focusedField = nil
            resetConfirmation = nil
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
                        .tint(AppColors.textOnAccent)
                }
                Text(isCreatingAccount ? "Create account" : "Sign In")
                    .font(AppTypography.button)
            }
            // Quiet primary: flat accent once the form is valid, a hairline
            // gray until then — never the multi-hue accent gradient.
            .foregroundStyle(canSubmitEmail ? AppColors.textOnAccent : AppColors.faint)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(canSubmitEmail ? AppColors.accent : AppColors.stroke)
            )
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(!canSubmitEmail || authService.isSigningIn)
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
                    .frame(width: 20, height: 20)
                Text("Continue with Google")
                    .font(AppTypography.button)
            }
            // Fixed near-black on the white plate rather than a theme token —
            // the plate stays white in both schemes, so a scheme-following
            // label would vanish on it in dark mode.
            .foregroundStyle(Color(white: 0.11))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(.white)
            )
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(authService.isSigningIn)
        .opacity(authService.isSigningIn ? 0.6 : 1)
    }

    private var accountSwitch: some View {
        HStack(spacing: 4) {
            Text(isCreatingAccount ? "Already have an account?" : "Don't have an account?")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
            Button(isCreatingAccount ? "Sign In" : "Sign Up") {
                Haptics.lightTap()
                resetConfirmation = nil
                authService.lastError = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCreatingAccount.toggle()
                }
            }
            .font(AppTypography.caption.weight(.bold))
            .foregroundStyle(AppColors.accent)
        }
        .padding(.top, 2)
    }

    // MARK: Chrome

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppColors.stroke)
                .frame(height: 1)
            Text("or continue with")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
            Rectangle()
                .fill(AppColors.stroke)
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private var signedInBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.positive)
            Text("Signed in — you're all set!")
                .appText(.headline)
                .foregroundStyle(AppColors.text)
        }
        .padding(.top, 4)
    }

    private var canSubmitEmail: Bool {
        email.contains("@") && password.count >= 6
    }
}

private extension View {
    /// Bordered field container with a focus ring, matching the reference's
    /// `focus-within:ring-2`.
    func authFieldChrome(focused: Bool) -> some View {
        font(AppTypography.body)
            .foregroundStyle(AppColors.text)
            .tint(AppColors.accent)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(AppColors.card2)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                            .stroke(
                                focused ? AppColors.accent : AppColors.stroke,
                                lineWidth: focused ? 2 : 1
                            )
                    )
            )
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

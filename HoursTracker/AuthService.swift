import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UIKit

// MARK: - Auth user model

struct AuthUser: Equatable {
    let uid: String
    let displayName: String?
    let email: String?
}

// MARK: - Auth service (Firebase + Sign in with Apple)

@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published private(set) var user: AuthUser?
    @Published private(set) var isSigningIn = false
    @Published var lastError: String?

    /// Fired after a successful sign-in so CloudSync can start listeners / migrate data.
    var onSignedIn: ((String) -> Void)?
    /// Fired when the user signs out.
    var onSignedOut: (() -> Void)?

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    private override init() {
        super.init()
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                self?.applyFirebaseUser(firebaseUser)
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var isSignedIn: Bool { user != nil }

    // MARK: - Sign in with Apple

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard let nonce = randomNonceString() else {
            // Should never happen in practice — kernel CSPRNG fails are
            // extraordinarily rare on iOS — but if it ever does we surface a
            // friendly error and abort the request instead of crashing the app.
            lastError = "Couldn't start Sign in with Apple. Please try again."
            return
        }
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleAuthorization(_ authorization: ASAuthorization) async {
        guard !isSigningIn else { return }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            lastError = "Invalid Apple credential."
            return
        }
        guard let nonce = currentNonce else {
            lastError = "Missing sign-in nonce. Try again."
            return
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            lastError = "Unable to read Apple identity token."
            return
        }

        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }

        do {
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: credential.fullName
            )
            let result = try await Auth.auth().signIn(with: firebaseCredential)
            let firebaseUser = result.user

            var displayName = firebaseUser.displayName ?? ""
            if displayName.isEmpty, let fullName = credential.fullName {
                let given = fullName.givenName ?? ""
                let family = fullName.familyName ?? ""
                displayName = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            }
            if displayName.isEmpty {
                displayName = UserDefaults.standard.string(forKey: "profile_display_name") ?? "Worker"
            }

            if !displayName.isEmpty {
                UserDefaults.standard.set(displayName, forKey: "profile_display_name")
                let change = firebaseUser.createProfileChangeRequest()
                change.displayName = displayName
                try? await change.commitChanges()
            }

            let email = firebaseUser.email ?? credential.email
            try await completeFirebaseSignIn(
                user: firebaseUser,
                preferredDisplayName: displayName.isEmpty ? nil : displayName,
                email: email
            )

            #if DEBUG
            print("Firebase uid: \(firebaseUser.uid)")
            print("→ Add to DeveloperConfig.developerUserIDs for the developer badge.")
            #endif
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Google

    func signInWithGoogle() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            lastError = "Google Sign-In is not configured."
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenter = Self.topViewController() else {
            lastError = "Couldn't open Google Sign-In."
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                lastError = "Missing Google identity token."
                return
            }
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: accessToken
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            try await completeFirebaseSignIn(
                user: authResult.user,
                preferredDisplayName: result.user.profile?.name,
                email: authResult.user.email
            )
        } catch {
            let nsError = error as NSError
            if nsError.domain == GIDSignInError.errorDomain,
               nsError.code == GIDSignInError.Code.canceled.rawValue {
                return
            }
            lastError = error.localizedDescription
        }
    }

    // MARK: - Email / password

    func signInWithEmail(email: String, password: String, createAccount: Bool) async {
        guard !isSigningIn else { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            lastError = "Enter a valid email address."
            return
        }
        guard password.count >= 6 else {
            lastError = "Password must be at least 6 characters."
            return
        }

        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }

        do {
            let authResult: AuthDataResult
            if createAccount {
                authResult = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
            } else {
                authResult = try await Auth.auth().signIn(withEmail: trimmedEmail, password: password)
            }
            try await completeFirebaseSignIn(
                user: authResult.user,
                preferredDisplayName: nil,
                email: trimmedEmail
            )
        } catch {
            lastError = friendlyAuthError(error)
        }
    }

    func sendPasswordReset(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.contains(".") else {
            lastError = "Enter a valid email address."
            return
        }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: trimmed)
        } catch {
            lastError = friendlyAuthError(error)
        }
    }

    /// Handles Google OAuth redirect URLs.
    @discardableResult
    static func handleIncomingURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func signOut() throws {
        try Auth.auth().signOut()
        user = nil
        onSignedOut?()
    }

    // MARK: - Profile doc

    /// Creates / refreshes the public profile doc at `users/{uid}` with the
    /// minimum fields needed for the friend-code lookup system to find the user.
    /// We deliberately do NOT publish `companyName` or `lookupEmail` here — both
    /// are local-only / unused by the friend system (lookup is by friendCode).
    func upsertUserDocument(uid: String, displayName: String, email: String?) async throws {
        _ = email // accepted for API compatibility; not persisted
        let data: [String: Any] = [
            "displayName": displayName,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await Firestore.firestore().collection("users").document(uid).setData(data, merge: true)
    }

    /// Retained as a no-op for any legacy callers from earlier versions that
    /// used email-based friend lookup. The current friend system uses 6-letter
    /// friend codes, so an email is no longer needed on the public profile doc.
    /// We still record it locally for non-network features (e.g. support flows).
    func updateLookupEmail(_ email: String) async {
        let lookup = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lookup.isEmpty else { return }
        UserDefaults.standard.set(lookup, forKey: "account_lookup_email")
    }

    // MARK: - Private

    private func completeFirebaseSignIn(
        user firebaseUser: FirebaseAuth.User,
        preferredDisplayName: String?,
        email: String?
    ) async throws {
        var displayName = preferredDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if displayName.isEmpty {
            displayName = firebaseUser.displayName ?? ""
        }
        if displayName.isEmpty {
            displayName = UserDefaults.standard.string(forKey: "profile_display_name") ?? ""
        }
        if displayName.isEmpty, let email, let prefix = email.split(separator: "@").first {
            displayName = String(prefix)
        }
        if displayName.isEmpty {
            displayName = "Worker"
        }

        if firebaseUser.displayName?.isEmpty != false {
            let change = firebaseUser.createProfileChangeRequest()
            change.displayName = displayName
            try? await change.commitChanges()
        }

        if !displayName.isEmpty {
            UserDefaults.standard.set(displayName, forKey: "profile_display_name")
        }

        try await upsertUserDocument(
            uid: firebaseUser.uid,
            displayName: displayName,
            email: email ?? firebaseUser.email
        )

        if let email = email ?? firebaseUser.email {
            await updateLookupEmail(email)
        }

        applyFirebaseUser(firebaseUser)
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .emailAlreadyInUse:
                return "That email is already registered. Try signing in instead."
            case .invalidEmail:
                return "That email address looks invalid."
            case .wrongPassword, .invalidCredential:
                return "Incorrect email or password."
            case .userNotFound:
                return "No account found for that email. Try creating one."
            case .weakPassword:
                return "Choose a stronger password (at least 6 characters)."
            case .networkError:
                return "Network error. Check your connection and try again."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

    private func applyFirebaseUser(_ firebaseUser: FirebaseAuth.User?) {
        let previousUID = user?.uid
        guard let firebaseUser else {
            user = nil
            if previousUID != nil {
                onSignedOut?()
            }
            return
        }
        user = AuthUser(
            uid: firebaseUser.uid,
            displayName: firebaseUser.displayName ?? UserDefaults.standard.string(forKey: "profile_display_name"),
            email: firebaseUser.email
        )
        if previousUID != firebaseUser.uid {
            onSignedIn?(firebaseUser.uid)
        }
    }

    /// Returns a random nonce string, or `nil` if the system CSPRNG fails.
    /// Callers must handle the `nil` case rather than crashing — see
    /// `prepareAppleSignInRequest` for the surfacing strategy.
    private func randomNonceString(length: Int = 32) -> String? {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard errorCode == errSecSuccess else { return nil }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

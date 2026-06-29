import Foundation
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

@MainActor
@Observable
final class AuthService {
    var currentUser: UserProfile?
    var authStateDetermined = false
    var isLoading = false
    var errorMessage: String?
    private(set) var onboardingRevision = 0

    /// Authenticated Firebase uid, whether or not the profile document has loaded.
    var currentUserId: String? {
        currentUser?.id ?? auth.currentUser?.uid
    }

    var isAuthenticated: Bool {
        #if DEBUG
        if DevAuthBypass.isEnabled, currentUser != nil {
            return true
        }
        #endif
        return auth.currentUser != nil
    }

    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    private static func onboardingKey(for userId: String) -> String {
        "pickems.onboarding.complete.\(userId)"
    }

    init() {
        #if DEBUG
        if DevAuthBypass.isEnabled {
            authStateDetermined = true
        }
        #endif

        authListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                #if DEBUG
                if DevAuthBypass.isEnabled { return }
                #endif
                self.authStateDetermined = true
                if let user {
                    await self.loadUserProfile(uid: user.uid)
                } else {
                    self.currentUser = nil
                }
            }
        }
    }

    #if DEBUG
    /// Skips Sign in with Apple / admin UI; uses anonymous Firebase auth for Firestore access.
    func activateDevBypass() async {
        guard DevAuthBypass.isEnabled else { return }
        authStateDetermined = true
        errorMessage = nil

        if auth.currentUser != nil {
            await refreshSession()
            return
        }

        do {
            let result = try await auth.signInAnonymously()
            await ensureUserProfile(uid: result.user.uid, displayName: DevAuthBypass.displayName)
        } catch {
            errorMessage = "Dev bypass auth failed: \(error.localizedDescription). Enable Anonymous sign-in in Firebase Console."
        }
    }
    #endif

    func hasCompletedOnboarding(for userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: Self.onboardingKey(for: userId))
    }

    func markOnboardingComplete(for userId: String) {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey(for: userId))
        onboardingRevision += 1
    }

    func prepareAppleSignIn() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    func signInWithApple(authorization: ASAuthorization) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleIDCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else {
            throw AuthError.invalidCredential
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        let result = try await auth.signIn(with: credential)
        let displayName = formattedName(from: appleIDCredential.fullName)
            ?? result.user.displayName
            ?? "Player"
        await ensureUserProfile(uid: result.user.uid, displayName: displayName)
    }

    #if DEBUG
    func signInAsAdmin(gatePassword: String, email: String, firebasePassword: String) async throws {
        guard gatePassword == DevAdminConfig.gatePassword else {
            throw AuthError.invalidAdminPassword
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedEmail.contains("@"), trimmedEmail.count >= 5 else {
            throw AuthError.adminInvalidEmail
        }
        guard firebasePassword.count >= 6 else {
            throw AuthError.adminPasswordTooWeak
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if auth.currentUser != nil {
            try auth.signOut()
        }

        let authResult = try await resolveAdminAuthSession(
            email: trimmedEmail,
            password: firebasePassword
        )
        await ensureUserProfile(uid: authResult.user.uid, displayName: DevAdminConfig.displayName)
    }

    private func resolveAdminAuthSession(email: String, password: String) async throws -> AuthDataResult {
        do {
            return try await createAdminUser(email: email, password: password)
        } catch {
            let nsError = error as NSError
            let code = AuthErrorCode(_bridgedNSError: nsError)
            if code == .emailAlreadyInUse {
                return try await signInExistingAdmin(email: email, password: password)
            }
            throw mapAdminFirebaseError(nsError, email: email)
        }
    }

    private func signInExistingAdmin(email: String, password: String) async throws -> AuthDataResult {
        do {
            return try await auth.signIn(withEmail: email, password: password)
        } catch {
            throw mapAdminFirebaseError(error as NSError, email: email)
        }
    }

    private func createAdminUser(email: String, password: String) async throws -> AuthDataResult {
        let result = try await auth.createUser(withEmail: email, password: password)
        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = DevAdminConfig.displayName
        try? await changeRequest.commitChanges()
        return result
    }

    private func mapAdminFirebaseError(_ error: NSError, email: String) -> AuthError {
        let code = AuthErrorCode(_bridgedNSError: error)
        switch code {
        case .operationNotAllowed:
            return .emailPasswordNotEnabled
        case .invalidEmail:
            return .adminInvalidEmail
        case .weakPassword:
            return .adminPasswordTooWeak
        case .wrongPassword, .invalidCredential:
            return .adminCredentialRejected(email: email, detail: error.localizedDescription)
        default:
            return .adminFirebaseError(detail: error.localizedDescription)
        }
    }
    #endif

    func updateDisplayName(_ name: String) async throws {
        guard let uid = auth.currentUser?.uid else { return }
        let changeRequest = auth.currentUser?.createProfileChangeRequest()
        changeRequest?.displayName = name
        try await changeRequest?.commitChanges()
        try await db.user(uid).updateData(["displayName": name])
        currentUser?.displayName = name
    }

    func updateAvatarURL(_ url: String?) async throws {
        guard let uid = auth.currentUser?.uid else { return }
        if let url {
            try await db.user(uid).updateData(["avatarImageURL": url])
            currentUser?.avatarImageURL = url
        } else {
            try await db.user(uid).updateData(["avatarImageURL": FieldValue.delete()])
            currentUser?.avatarImageURL = nil
        }
    }

    func signOut() throws {
        try auth.signOut()
        currentUser = nil
        authStateDetermined = true
        onboardingRevision += 1
    }

    func refreshSession() async {
        guard let uid = auth.currentUser?.uid else { return }
        await loadUserProfile(uid: uid)
    }

    private func loadUserProfile(uid: String) async {
        do {
            let doc = try await db.user(uid).getDocument()
            if let profile = try? doc.data(as: UserProfile.self) {
                currentUser = profile
                errorMessage = nil
                return
            }
        } catch {
            let nsError = error as NSError
            let isOffline = nsError.domain == FirestoreErrorDomain
                && nsError.code == FirestoreErrorCode.unavailable.rawValue
            if !isOffline {
                errorMessage = error.localizedDescription
            }
        }

        applyLocalProfileFallback(uid: uid)
    }

    private func ensureUserProfile(uid: String, displayName: String) async {
        let ref = db.user(uid)
        let fallback = UserProfile(
            id: uid,
            displayName: displayName,
            avatarColorHex: cachedAvatarColor(for: uid) ?? AvatarColors.randomHex(),
            avatarImageURL: nil,
            createdAt: Date()
        )

        do {
            let doc = try await ref.getDocument()
            if doc.exists, let profile = try? doc.data(as: UserProfile.self) {
                currentUser = profile
                cacheAvatarColor(profile.avatarColorHex, for: uid)
                errorMessage = nil
                return
            }
            try await ref.setData(from: fallback)
            currentUser = fallback
            cacheAvatarColor(fallback.avatarColorHex, for: uid)
            errorMessage = nil
        } catch {
            // Auth succeeded — keep going with a local profile; Firestore syncs when online.
            currentUser = fallback
            cacheAvatarColor(fallback.avatarColorHex, for: uid)
            try? await ref.setData(from: fallback, merge: true)
        }
    }

    private func applyLocalProfileFallback(uid: String) {
        guard let firebaseUser = auth.currentUser else { return }
        let color = cachedAvatarColor(for: uid) ?? AvatarColors.randomHex()
        currentUser = UserProfile(
            id: uid,
            displayName: firebaseUser.displayName ?? "Player",
            avatarColorHex: color,
            avatarImageURL: nil,
            createdAt: Date()
        )
        cacheAvatarColor(color, for: uid)
    }

    private func cachedAvatarColor(for uid: String) -> String? {
        UserDefaults.standard.string(forKey: "pickems.avatar.\(uid)")
    }

    private func cacheAvatarColor(_ hex: String, for uid: String) {
        UserDefaults.standard.set(hex, forKey: "pickems.avatar.\(uid)")
    }

    private func formattedName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components)
        return name.isEmpty ? nil : name
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            randoms.forEach { random in
                if remaining == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    enum AuthError: LocalizedError {
        case invalidCredential
        case invalidAdminPassword
        case adminInvalidEmail
        case adminPasswordTooWeak
        case adminCredentialRejected(email: String, detail: String)
        case adminFirebaseError(detail: String)
        case emailPasswordNotEnabled

        var errorDescription: String? {
            switch self {
            case .invalidCredential: return "Invalid Apple Sign In credential."
            case .invalidAdminPassword: return "Incorrect admin gate password."
            case .adminInvalidEmail: return "Enter a valid email for the Firebase admin account."
            case .adminPasswordTooWeak: return "Firebase password must be at least 6 characters."
            case .adminCredentialRejected(let email, let detail):
                return """
                Firebase rejected sign-in for \(email).
                \(detail)
                Use the exact email and password from Firebase Console → Authentication → Users, \
                or delete that user and tap Sign In to auto-create.
                """
            case .adminFirebaseError(let detail):
                return "Firebase auth error: \(detail)"
            case .emailPasswordNotEnabled:
                return """
                Email/Password sign-in is disabled. In Firebase Console → Authentication → Sign-in method, \
                enable Email/Password, then run: npx firebase-tools deploy --only auth
                """
            }
        }
    }
}

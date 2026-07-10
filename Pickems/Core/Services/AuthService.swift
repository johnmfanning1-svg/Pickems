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
    /// Observable Firebase session flag. Do not read `Auth.auth().currentUser` from views —
    /// that value is not tracked by `@Observable`, so RootView would never leave SignInView.
    private(set) var isSignedIn = false
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
        return isSignedIn
    }

    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    /// Bumps on intentional sign-out-before-sign-in so stale listener tasks cannot wipe the new session.
    private var authEpoch = 0

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
                let epoch = self.authEpoch
                self.authStateDetermined = true
                if let user {
                    self.applySignedIn(uid: user.uid)
                    await self.loadUserProfile(uid: user.uid)
                    // A newer sign-in/out started while we were loading — don't clobber it.
                    guard epoch == self.authEpoch else { return }
                    self.applySignedIn(uid: user.uid)
                } else {
                    guard epoch == self.authEpoch else { return }
                    self.applySignedOut()
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
            applySignedIn(uid: auth.currentUser?.uid)
            return
        }

        do {
            let result = try await auth.signInAnonymously()
            await ensureUserProfile(uid: result.user.uid, displayName: DevAuthBypass.displayName)
            applySignedIn(uid: result.user.uid)
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
        applySignedIn(uid: result.user.uid)
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        let trimmedEmail = Self.normalizedEmail(email)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.validateEmail(trimmedEmail)
        try Self.validatePassword(password)
        guard !trimmedName.isEmpty else {
            throw AuthError.displayNameRequired
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await replaceSessionIfNeeded()
            let result = try await auth.createUser(withEmail: trimmedEmail, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = trimmedName
            try? await changeRequest.commitChanges()
            await ensureUserProfile(uid: result.user.uid, displayName: trimmedName)
            applySignedIn(uid: result.user.uid)
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
            throw error
        } catch {
            let mapped = Self.mapEmailPasswordError(error as NSError)
            errorMessage = mapped.localizedDescription
            throw mapped
        }
    }

    func signIn(email: String, password: String) async throws {
        let trimmedEmail = Self.normalizedEmail(email)
        try Self.validateEmail(trimmedEmail)
        guard !password.isEmpty else {
            throw AuthError.passwordRequired
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await replaceSessionIfNeeded()
            let result = try await auth.signIn(withEmail: trimmedEmail, password: password)
            let displayName = result.user.displayName ?? "Player"
            await ensureUserProfile(uid: result.user.uid, displayName: displayName)
            applySignedIn(uid: result.user.uid)
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
            throw error
        } catch {
            let mapped = Self.mapEmailPasswordError(error as NSError)
            errorMessage = mapped.localizedDescription
            throw mapped
        }
    }

    func sendPasswordReset(email: String) async throws {
        let trimmedEmail = Self.normalizedEmail(email)
        try Self.validateEmail(trimmedEmail)

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await auth.sendPasswordReset(withEmail: trimmedEmail)
        } catch {
            let mapped = Self.mapEmailPasswordError(error as NSError)
            errorMessage = mapped.localizedDescription
            throw mapped
        }
    }

    #if DEBUG
    func signInAsAdmin(gatePassword: String, email: String, firebasePassword: String) async throws {
        guard gatePassword == DevAdminConfig.gatePassword else {
            throw AuthError.invalidAdminPassword
        }

        let trimmedEmail = Self.normalizedEmail(email)
        try Self.validateEmail(trimmedEmail)
        try Self.validatePassword(firebasePassword)

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await replaceSessionIfNeeded()
            let authResult = try await resolveAdminAuthSession(
                email: trimmedEmail,
                password: firebasePassword
            )
            await ensureUserProfile(uid: authResult.user.uid, displayName: DevAdminConfig.displayName)
            applySignedIn(uid: authResult.user.uid)
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
            throw error
        } catch {
            let mapped = Self.mapEmailPasswordError(error as NSError)
            errorMessage = mapped.localizedDescription
            throw mapped
        }
    }

    private func resolveAdminAuthSession(email: String, password: String) async throws -> AuthDataResult {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = DevAdminConfig.displayName
            try? await changeRequest.commitChanges()
            return result
        } catch {
            let nsError = error as NSError
            let code = AuthErrorCode(_bridgedNSError: nsError)
            if code == .emailAlreadyInUse {
                return try await auth.signIn(withEmail: email, password: password)
            }
            throw Self.mapEmailPasswordError(nsError)
        }
    }
    #endif

    private static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func validateEmail(_ email: String) throws {
        guard email.contains("@"), email.contains("."), email.count >= 5 else {
            throw AuthError.invalidEmail
        }
    }

    private static func validatePassword(_ password: String) throws {
        guard password.count >= 6 else {
            throw AuthError.passwordTooWeak
        }
    }

    private static func mapEmailPasswordError(_ error: NSError) -> AuthError {
        let code = AuthErrorCode(_bridgedNSError: error)
        switch code {
        case .operationNotAllowed:
            return .emailPasswordNotEnabled
        case .invalidEmail:
            return .invalidEmail
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .weakPassword:
            return .passwordTooWeak
        case .wrongPassword, .invalidCredential, .userNotFound:
            return .invalidEmailOrPassword
        case .userDisabled:
            return .accountDisabled
        case .tooManyRequests:
            return .tooManyRequests
        case .networkError:
            return .networkError
        default:
            return .firebaseError(detail: error.localizedDescription)
        }
    }

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

    func updateFavoriteTeam(_ team: FavoriteTeam?) async throws {
        guard let uid = currentUserId else { return }
        var data: [String: Any] = [:]
        if let team {
            data = [
                "favoriteTeamId": team.id,
                "favoriteTeamName": team.name,
                "favoriteTeamAbbreviation": team.abbreviation,
                "favoriteTeamLogoURL": team.resolvedLogoURL,
            ]
        } else {
            data = [
                "favoriteTeamId": FieldValue.delete(),
                "favoriteTeamName": FieldValue.delete(),
                "favoriteTeamAbbreviation": FieldValue.delete(),
                "favoriteTeamLogoURL": FieldValue.delete(),
            ]
        }
        try await db.user(uid).updateData(data)
        currentUser?.favoriteTeamId = team?.id
        currentUser?.favoriteTeamName = team?.name
        currentUser?.favoriteTeamAbbreviation = team?.abbreviation
        currentUser?.favoriteTeamLogoURL = team?.resolvedLogoURL
        if let team {
            markFavoriteTeamPromptDismissed(for: uid)
        }
    }

    private static func favoriteTeamPromptKey(for userId: String) -> String {
        "pickems.favoriteTeam.promptDismissed.\(userId)"
    }

    func hasDismissedFavoriteTeamPrompt(for userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: Self.favoriteTeamPromptKey(for: userId))
    }

    func markFavoriteTeamPromptDismissed(for userId: String) {
        UserDefaults.standard.set(true, forKey: Self.favoriteTeamPromptKey(for: userId))
    }

    func signOut() throws {
        authEpoch += 1
        try auth.signOut()
        applySignedOut()
        authStateDetermined = true
        onboardingRevision += 1
    }

    func refreshSession() async {
        guard let uid = auth.currentUser?.uid else { return }
        await loadUserProfile(uid: uid)
        applySignedIn(uid: uid)
    }

    /// Clears any existing Firebase session before email/password auth so we don't mix identities.
    private func replaceSessionIfNeeded() async throws {
        guard auth.currentUser != nil else { return }
        authEpoch += 1
        try auth.signOut()
        // Keep isSignedIn true-ish UX via loading spinner; clear profile until new session lands.
        currentUser = nil
        isSignedIn = false
    }

    private func applySignedIn(uid: String?) {
        guard uid != nil else { return }
        isSignedIn = true
        authStateDetermined = true
    }

    private func applySignedOut() {
        currentUser = nil
        isSignedIn = false
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
        case invalidEmail
        case passwordRequired
        case passwordTooWeak
        case displayNameRequired
        case emailAlreadyInUse
        case invalidEmailOrPassword
        case accountDisabled
        case tooManyRequests
        case networkError
        case emailPasswordNotEnabled
        case firebaseError(detail: String)

        var errorDescription: String? {
            switch self {
            case .invalidCredential:
                return "Invalid Apple Sign In credential."
            case .invalidAdminPassword:
                return "Incorrect admin gate password."
            case .invalidEmail:
                return "Enter a valid email address."
            case .passwordRequired:
                return "Enter your password."
            case .passwordTooWeak:
                return "Password must be at least 6 characters."
            case .displayNameRequired:
                return "Enter a display name so your crew knows who you are."
            case .emailAlreadyInUse:
                return "An account already exists for that email. Sign in instead."
            case .invalidEmailOrPassword:
                return "Incorrect email or password."
            case .accountDisabled:
                return "This account has been disabled."
            case .tooManyRequests:
                return "Too many attempts. Try again in a few minutes."
            case .networkError:
                return "Network error. Check your connection and try again."
            case .emailPasswordNotEnabled:
                return """
                Email/Password sign-in is disabled. In Firebase Console → Authentication → Sign-in method, \
                enable Email/Password, then run: npx firebase-tools deploy --only auth
                """
            case .firebaseError(let detail):
                return "Sign-in error: \(detail)"
            }
        }
    }
}

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

    /// Lazily resolved so `AppState()` construction cannot call into Firebase before
    /// `FirebaseBootstrap.configureIfNeeded()` finishes (TestFlight launch abort).
    /// `@ObservationIgnored` keeps these as true `lazy` storage — `@Observable` would
    /// otherwise rewrite them into computed init-accessors and fail to compile.
    @ObservationIgnored
    @ObservationIgnored private lazy var auth = Auth.auth()
    @ObservationIgnored
    @ObservationIgnored private lazy var db = Firestore.firestore()
    @ObservationIgnored
    private var authListener: AuthStateDidChangeListenerHandle?
    @ObservationIgnored
    private var currentNonce: String?
    /// Bumps on intentional sign-out-before-sign-in so stale listener tasks cannot wipe the new session.
    @ObservationIgnored
    private var authEpoch = 0
    @ObservationIgnored
    private var didStart = false

    private static func onboardingKey(for userId: String) -> String {
        "pickems.onboarding.complete.\(userId)"
    }

    init() {
        #if DEBUG
        if DevAuthBypass.isEnabled {
            authStateDetermined = true
        }
        #endif
    }

    /// Attach the auth state listener. Call only after Firebase is configured.
    func start() {
        guard !didStart else { return }
        didStart = true

        authListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                #if DEBUG
                if DevAuthBypass.isEnabled { return }
                #endif
                let epoch = self.authEpoch
                self.authStateDetermined = true
                AppEvents.track(.authStateChanged, metadata: [
                    "signed_in": user != nil ? "true" : "false",
                    "uid": AppEvents.shortUID(user?.uid),
                    "epoch": "\(epoch)",
                ])
                if let user {
                    self.applySignedIn(uid: user.uid)
                    await self.loadUserProfile(uid: user.uid)
                    // A newer sign-in/out started while we were loading — don't clobber it.
                    guard epoch == self.authEpoch else {
                        AppEvents.track(.authEpochStaleIgnored, metadata: [
                            "uid": AppEvents.shortUID(user.uid),
                            "epoch": "\(epoch)",
                            "current_epoch": "\(self.authEpoch)",
                        ])
                        return
                    }
                    self.applySignedIn(uid: user.uid)
                } else {
                    guard epoch == self.authEpoch else {
                        AppEvents.track(.authEpochStaleIgnored, metadata: [
                            "epoch": "\(epoch)",
                            "current_epoch": "\(self.authEpoch)",
                        ])
                        return
                    }
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
        AppEvents.track(.onboardingMarkedComplete, metadata: [
            "uid": AppEvents.shortUID(userId),
            "revision": "\(onboardingRevision)",
        ])
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
        AppEvents.track(.authAppleStarted)

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleIDCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else {
            let error = AuthError.invalidCredential
            AppEvents.failure(.authAppleFailed, error: error, metadata: ["reason": "missing_credential_or_nonce"])
            throw error
        }

        do {
            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            let result = try await auth.signIn(with: credential)
            let first = appleIDCredential.fullName?.givenName
            let last = appleIDCredential.fullName?.familyName
            let displayName = result.user.displayName
                ?? suggestedUsername(firstName: first, lastName: last, uid: result.user.uid)
            await ensureUserProfile(
                uid: result.user.uid,
                displayName: displayName,
                firstName: first,
                lastName: last
            )
            // Persist legal name when Apple provides it (only on first authorization).
            var legalName: [String: Any] = [:]
            if let first { legalName["firstName"] = first }
            if let last { legalName["lastName"] = last }
            if !legalName.isEmpty {
                try? await db.user(result.user.uid).setData(legalName, merge: true)
                if currentUser?.firstName == nil { currentUser?.firstName = first }
                if currentUser?.lastName == nil { currentUser?.lastName = last }
            }
            applySignedIn(uid: result.user.uid)
            AppEvents.track(.authAppleSucceeded, metadata: [
                "uid": AppEvents.shortUID(result.user.uid),
            ])
        } catch {
            errorMessage = error.localizedDescription
            AppEvents.failure(.authAppleFailed, error: error)
            throw error
        }
    }

    func signUp(
        email: String,
        password: String,
        displayName: String,
        firstName: String,
        lastName: String
    ) async throws {
        let trimmedEmail = Self.normalizedEmail(email)
        try Self.validateEmail(trimmedEmail)
        try Self.validatePassword(password)
        let username: String
        switch DisplayNameRules.validate(displayName) {
        case .success(let value):
            username = value
        case .failure(let error):
            throw mapDisplayNameValidation(error)
        }
        let first: String
        let last: String
        switch PersonNameRules.validate(firstName, field: "first name") {
        case .success(let value): first = value
        case .failure(let error):
            throw AuthError.firebaseError(detail: error.localizedDescription ?? "Enter your first name.")
        }
        switch PersonNameRules.validate(lastName, field: "last name") {
        case .success(let value): last = value
        case .failure(let error):
            throw AuthError.firebaseError(detail: error.localizedDescription ?? "Enter your last name.")
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        AppEvents.track(.authSignUpStarted)

        do {
            try await replaceSessionIfNeeded()
            let result = try await auth.createUser(withEmail: trimmedEmail, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = username
            do {
                try await changeRequest.commitChanges()
            } catch {
                AppLog.error(AppLog.auth, "displayName commit failed after sign-up", error: error, metadata: [
                    "uid": AppEvents.shortUID(result.user.uid),
                ])
            }
            await ensureUserProfile(
                uid: result.user.uid,
                displayName: username,
                firstName: first,
                lastName: last
            )
            // Reserve unique username before treating sign-up as complete.
            do {
                try await claimDisplayName(
                    username,
                    key: DisplayNameRules.uniquenessKey(for: username),
                    previousKey: "",
                    uid: result.user.uid
                )
            } catch {
                try? await result.user.delete()
                applySignedOut()
                throw error
            }
            try? await db.user(result.user.uid).updateData([
                "displayName": username,
                "handleKey": DisplayNameRules.uniquenessKey(for: username),
                "firstName": first,
                "lastName": last,
            ])
            currentUser?.displayName = username
            currentUser?.handleKey = DisplayNameRules.uniquenessKey(for: username)
            currentUser?.firstName = first
            currentUser?.lastName = last
            applySignedIn(uid: result.user.uid)
            AppEvents.track(.authSignUpSucceeded, metadata: [
                "uid": AppEvents.shortUID(result.user.uid),
            ])
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
            AppEvents.failure(.authSignUpFailed, error: error)
            throw error
        } catch {
            let mapped = Self.mapEmailPasswordError(error as NSError)
            errorMessage = mapped.localizedDescription
            AppEvents.failure(.authSignUpFailed, error: mapped, metadata: [
                "underlying": AppLog.describe(error),
            ])
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
        AppEvents.track(.authSignInStarted)

        do {
            try await replaceSessionIfNeeded()
            let result = try await auth.signIn(withEmail: trimmedEmail, password: password)
            let displayName = result.user.displayName ?? "Player"
            await ensureUserProfile(uid: result.user.uid, displayName: displayName)
            applySignedIn(uid: result.user.uid)
            AppEvents.track(.authSignInSucceeded, metadata: [
                "uid": AppEvents.shortUID(result.user.uid),
            ])
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
            AppEvents.failure(.authSignInFailed, error: error)
            throw error
        } catch {
            let mapped = Self.mapEmailPasswordError(error as NSError)
            errorMessage = mapped.localizedDescription
            AppEvents.failure(.authSignInFailed, error: mapped, metadata: [
                "underlying": AppLog.describe(error),
            ])
            throw mapped
        }
    }

    func sendPasswordReset(email: String) async throws {
        let trimmedEmail = Self.normalizedEmail(email)
        try Self.validateEmail(trimmedEmail)

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        AppEvents.track(.authPasswordResetStarted)

        do {
            try await auth.sendPasswordReset(withEmail: trimmedEmail)
            AppEvents.track(.authPasswordResetSucceeded)
        } catch {
            let mapped = Self.mapEmailPasswordError(error as NSError)
            errorMessage = mapped.localizedDescription
            AppEvents.failure(.authPasswordResetFailed, error: mapped)
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

    /// Unique public username shown in leagues.
    func updateDisplayName(_ name: String) async throws {
        guard let uid = auth.currentUser?.uid else { return }
        let validated: String
        switch DisplayNameRules.validate(name) {
        case .success(let value):
            validated = value
        case .failure(let error):
            throw mapDisplayNameValidation(error)
        }
        let newKey = DisplayNameRules.uniquenessKey(for: validated)
        let previousKey = currentUser?.handleKey
            ?? DisplayNameRules.uniquenessKey(for: currentUser?.displayName ?? "")

        try await claimDisplayName(validated, key: newKey, previousKey: previousKey, uid: uid)

        let changeRequest = auth.currentUser?.createProfileChangeRequest()
        changeRequest?.displayName = validated
        try await changeRequest?.commitChanges()
        try await db.user(uid).updateData([
            "displayName": validated,
            "handleKey": newKey,
        ])
        currentUser?.displayName = validated
        currentUser?.handleKey = newKey
        AppEvents.track(.authDisplayNameUpdated, metadata: [
            "uid": AppEvents.shortUID(uid),
        ])
    }

    func updateLegalName(firstName: String, lastName: String) async throws {
        guard let uid = auth.currentUser?.uid else { return }
        let first: String
        let last: String
        switch PersonNameRules.validate(firstName, field: "first name") {
        case .success(let value): first = value
        case .failure(let error): throw AuthError.firebaseError(detail: error.localizedDescription ?? "")
        }
        switch PersonNameRules.validate(lastName, field: "last name") {
        case .success(let value): last = value
        case .failure(let error): throw AuthError.firebaseError(detail: error.localizedDescription ?? "")
        }
        try await db.user(uid).updateData([
            "firstName": first,
            "lastName": last,
        ])
        currentUser?.firstName = first
        currentUser?.lastName = last
    }

    /// `.available` / `.taken` / `.invalid` for live username feedback before save.
    func checkUsernameAvailability(_ raw: String) async -> UsernameAvailability {
        switch DisplayNameRules.validate(raw) {
        case .failure(let error):
            return .invalid(error)
        case .success(let username):
            let key = DisplayNameRules.uniquenessKey(for: username)
            if key == (currentUser?.handleKey ?? DisplayNameRules.uniquenessKey(for: currentUser?.displayName ?? "")) {
                return .available(username)
            }
            do {
                let snap = try await db.handle(key).getDocument()
                if snap.exists {
                    let owner = snap.data()?["userId"] as? String
                    if owner == auth.currentUser?.uid {
                        return .available(username)
                    }
                    return .taken
                }
                return .available(username)
            } catch {
                return .invalid(.invalidCharacters)
            }
        }
    }

    enum UsernameAvailability: Equatable {
        case available(String)
        case taken
        case invalid(DisplayNameRules.ValidationError)
    }

    private func mapDisplayNameValidation(_ error: DisplayNameRules.ValidationError) -> AuthError {
        switch error {
        case .tooShort: return .displayNameTooShort
        case .tooLong: return .displayNameTooLong
        case .invalidCharacters: return .displayNameInvalid
        case .taken: return .displayNameTaken
        }
    }

    /// Atomically reserves `handles/{key}` so nicknames stay unique across the app.
    private func claimDisplayName(
        _ displayName: String,
        key: String,
        previousKey: String,
        uid: String
    ) async throws {
        let newRef = db.handle(key)
        let shouldReleasePrevious = !previousKey.isEmpty && previousKey != key
        let oldRef = shouldReleasePrevious ? db.handle(previousKey) : nil

        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let newSnap = try transaction.getDocument(newRef)
                    if newSnap.exists {
                        let owner = newSnap.data()?["userId"] as? String
                        if owner != uid {
                            let taken = NSError(
                                domain: "Pickems.HandleClaim",
                                code: 409,
                                userInfo: [NSLocalizedDescriptionKey: "taken"]
                            )
                            errorPointer?.pointee = taken
                            return nil
                        }
                    }
                    if let oldRef {
                        let oldSnap = try transaction.getDocument(oldRef)
                        if oldSnap.exists,
                           (oldSnap.data()?["userId"] as? String) == uid {
                            transaction.deleteDocument(oldRef)
                        }
                    }
                    transaction.setData([
                        "userId": uid,
                        "displayName": displayName,
                        "updatedAt": FieldValue.serverTimestamp(),
                    ], forDocument: newRef)
                    return true
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            let ns = error as NSError
            if ns.domain == "Pickems.HandleClaim", ns.code == 409 {
                throw AuthError.displayNameTaken
            }
            if ns.domain == FirestoreErrorDomain,
               ns.code == FirestoreErrorCode.permissionDenied.rawValue {
                throw AuthError.firebaseError(
                    detail: "Couldn't reserve that username. Try again in a moment."
                )
            }
            throw AuthError.firebaseError(detail: error.localizedDescription)
        }
    }

    private func releaseDisplayNameHandle(for uid: String) async {
        let key = currentUser?.handleKey
            ?? DisplayNameRules.uniquenessKey(for: currentUser?.displayName ?? "")
        guard !key.isEmpty else { return }
        let ref = db.handle(key)
        do {
            let snap = try await ref.getDocument()
            if snap.exists, (snap.data()?["userId"] as? String) == uid {
                try await ref.delete()
            }
        } catch {
            AppLog.error(AppLog.auth, "handle release failed", error: error, metadata: [
                "uid": AppEvents.shortUID(uid),
            ])
        }
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
        do {
            try await db.user(uid).updateData(data)
            currentUser?.favoriteTeamId = team?.id
            currentUser?.favoriteTeamName = team?.name
            currentUser?.favoriteTeamAbbreviation = team?.abbreviation
            currentUser?.favoriteTeamLogoURL = team?.resolvedLogoURL
            if let team {
                markFavoriteTeamPromptDismissed(for: uid)
                AppEvents.track(.favoriteTeamSelected, metadata: [
                    "uid": AppEvents.shortUID(uid),
                    "team_id": team.id,
                    "team": team.abbreviation,
                ])
            } else {
                AppEvents.track(.favoriteTeamCleared, metadata: [
                    "uid": AppEvents.shortUID(uid),
                ])
            }
        } catch {
            AppEvents.failure(.favoriteTeamFailed, error: error, metadata: [
                "uid": AppEvents.shortUID(uid),
                "team_id": team?.id ?? "nil",
            ])
            throw error
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
        let uid = currentUserId
        try auth.signOut()
        applySignedOut()
        authStateDetermined = true
        onboardingRevision += 1
        AppEvents.track(.authSignOut, metadata: [
            "uid": AppEvents.shortUID(uid),
        ])
        CrashReport.setUserID(nil)
    }

    /// Permanently deletes the signed-in user's Auth account and profile data (Guideline 5.1.1(v)).
    /// Caller should leave/dissolve leagues first.
    func deleteAccount() async throws {
        guard let user = auth.currentUser else {
            throw AuthError.notSignedIn
        }
        let uid = user.uid
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        AppEvents.track(.authDeleteAccountStarted, metadata: [
            "uid": AppEvents.shortUID(uid),
        ])

        do {
            await releaseDisplayNameHandle(for: uid)
            try? await AvatarService.deleteAvatar(userId: uid)
            try? await db.user(uid).delete()
            UserDefaults.standard.removeObject(forKey: Self.onboardingKey(for: uid))
            UserDefaults.standard.removeObject(forKey: Self.favoriteTeamPromptKey(for: uid))

            authEpoch += 1
            try await user.delete()
            applySignedOut()
            authStateDetermined = true
            onboardingRevision += 1
            AppEvents.track(.authDeleteAccountSucceeded, metadata: [
                "uid": AppEvents.shortUID(uid),
            ])
            CrashReport.setUserID(nil)
        } catch {
            let mapped = Self.mapDeleteAccountError(error as NSError)
            errorMessage = mapped.localizedDescription
            AppEvents.failure(.authDeleteAccountFailed, error: mapped, metadata: [
                "uid": AppEvents.shortUID(uid),
            ])
            throw mapped
        }
    }

    private static func mapDeleteAccountError(_ error: NSError) -> AuthError {
        let code = AuthErrorCode(_bridgedNSError: error)
        switch code {
        case .requiresRecentLogin:
            return .requiresRecentLogin
        default:
            return mapEmailPasswordError(error)
        }
    }

    func refreshSession() async {
        guard let uid = auth.currentUser?.uid else {
            AppLog.notice(AppLog.auth, "refreshSession skipped — no Firebase user")
            return
        }
        await loadUserProfile(uid: uid)
        applySignedIn(uid: uid)
    }

    /// Clears any existing Firebase session before email/password auth so we don't mix identities.
    private func replaceSessionIfNeeded() async throws {
        guard auth.currentUser != nil else { return }
        authEpoch += 1
        AppLog.info(AppLog.auth, "replacing existing session before email auth", metadata: [
            "epoch": "\(authEpoch)",
        ])
        try auth.signOut()
        // Keep isSignedIn true-ish UX via loading spinner; clear profile until new session lands.
        currentUser = nil
        isSignedIn = false
    }

    private func applySignedIn(uid: String?) {
        guard let uid else { return }
        isSignedIn = true
        authStateDetermined = true
        CrashReport.setUserID(uid)
        CrashReport.setValue("true", forKey: "is_signed_in")
    }

    private func applySignedOut() {
        currentUser = nil
        isSignedIn = false
        CrashReport.setUserID(nil)
        CrashReport.setValue("false", forKey: "is_signed_in")
    }

    private func loadUserProfile(uid: String) async {
        do {
            let doc = try await db.user(uid).getDocument()
            if let profile = try? doc.data(as: UserProfile.self) {
                currentUser = profile
                errorMessage = nil
                AppEvents.track(.authProfileLoaded, metadata: [
                    "uid": AppEvents.shortUID(uid),
                    "source": "firestore",
                    "has_favorite_team": profile.favoriteTeamId != nil ? "true" : "false",
                ])
                return
            }
            AppLog.notice(AppLog.auth, "profile document missing or undecodable — using fallback", metadata: [
                "uid": AppEvents.shortUID(uid),
                "exists": doc.exists ? "true" : "false",
            ])
        } catch {
            let nsError = error as NSError
            let isOffline = nsError.domain == FirestoreErrorDomain
                && nsError.code == FirestoreErrorCode.unavailable.rawValue
            if !isOffline {
                errorMessage = error.localizedDescription
                AppEvents.failure(.authProfileSyncFailed, error: error, metadata: [
                    "uid": AppEvents.shortUID(uid),
                    "phase": "load",
                ])
            } else {
                AppLog.info(AppLog.auth, "profile load offline — using fallback", metadata: [
                    "uid": AppEvents.shortUID(uid),
                ])
            }
        }

        applyLocalProfileFallback(uid: uid)
    }

    private func ensureUserProfile(
        uid: String,
        displayName: String,
        firstName: String? = nil,
        lastName: String? = nil
    ) async {
        let ref = db.user(uid)
        let fallback = UserProfile(
            id: uid,
            displayName: displayName,
            firstName: firstName,
            lastName: lastName,
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
                AppEvents.track(.authProfileLoaded, metadata: [
                    "uid": AppEvents.shortUID(uid),
                    "source": "ensure_existing",
                ])
                return
            }
            try await ref.setData(from: fallback)
            currentUser = fallback
            cacheAvatarColor(fallback.avatarColorHex, for: uid)
            errorMessage = nil
            AppEvents.track(.authProfileLoaded, metadata: [
                "uid": AppEvents.shortUID(uid),
                "source": "ensure_created",
            ])
        } catch {
            // Auth succeeded — keep going with a local profile; Firestore syncs when online.
            currentUser = fallback
            cacheAvatarColor(fallback.avatarColorHex, for: uid)
            AppEvents.failure(.authProfileSyncFailed, error: error, metadata: [
                "uid": AppEvents.shortUID(uid),
                "phase": "ensure",
            ], recordNonFatal: true)
            AppEvents.track(.authProfileFallback, metadata: [
                "uid": AppEvents.shortUID(uid),
            ])
            do {
                try await ref.setData(from: fallback, merge: true)
            } catch {
                AppLog.error(AppLog.auth, "profile merge retry failed", error: error, metadata: [
                    "uid": AppEvents.shortUID(uid),
                ])
            }
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
        AppEvents.track(.authProfileFallback, metadata: [
            "uid": AppEvents.shortUID(uid),
            "source": "local",
        ])
    }

    private func cachedAvatarColor(for uid: String) -> String? {
        UserDefaults.standard.string(forKey: "pickems.avatar.\(uid)")
    }

    private func cacheAvatarColor(_ hex: String, for uid: String) {
        UserDefaults.standard.set(hex, forKey: "pickems.avatar.\(uid)")
    }

    private func suggestedUsername(firstName: String?, lastName: String?, uid: String) -> String {
        let base = [firstName, lastName]
            .compactMap { $0?.lowercased() }
            .joined()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        if base.count >= DisplayNameRules.minLength {
            return String(base.prefix(DisplayNameRules.maxLength))
        }
        return "user_" + String(uid.prefix(6)).lowercased()
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
        case displayNameTooShort
        case displayNameTooLong
        case displayNameInvalid
        case displayNameTaken
        case emailAlreadyInUse
        case invalidEmailOrPassword
        case accountDisabled
        case tooManyRequests
        case networkError
        case emailPasswordNotEnabled
        case notSignedIn
        case requiresRecentLogin
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
                return "Enter a username so your crew knows who you are."
            case .displayNameTooShort:
                return DisplayNameRules.ValidationError.tooShort.errorDescription
            case .displayNameTooLong:
                return DisplayNameRules.ValidationError.tooLong.errorDescription
            case .displayNameInvalid:
                return DisplayNameRules.ValidationError.invalidCharacters.errorDescription
            case .displayNameTaken:
                return DisplayNameRules.ValidationError.taken.errorDescription
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
            case .notSignedIn:
                return "You need to be signed in to delete your account."
            case .requiresRecentLogin:
                return "For security, sign out, sign back in, then delete your account."
            case .firebaseError(let detail):
                return "Sign-in error: \(detail)"
            }
        }
    }
}

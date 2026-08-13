import Foundation
import FirebaseCore
import FirebaseFirestore

enum AppTab: Hashable {
    case home
    case leagues
    case selections
    case pickems
    case profile
}

@MainActor
@Observable
final class AppState {
    let authService = AuthService()
    let groupService = GroupService()
    let pickService = PickService()
    /// One draft for Picks tab and Groups > Group Slate / Group Pickems. Separate
    /// view-model instances were why Group clears kept missing the Picks tab.
    let picksViewModel = PicksViewModel()
    let chatService = ChatService()
    let notificationService = NotificationService()
    let appTheme = AppTheme()

    var selectedTab: AppTab = .home
    var pendingInviteCode: String?
    var showJoinGroupSheet = false
    var showFavoriteTeamPicker = false
    /// Set by selection-deadline push; Selections tab presents the setter sheet.
    var pendingSelectionDeadlinePrompt = false
    /// League to select when a push/deep link includes `groupId`.
    var pendingDeepLinkGroupId: String?
    /// Set when Firebase failed to boot; RootView can show a non-crash error screen.
    var firebaseBootFailed = false
    /// In-app “Stay on time” prompt before the iOS notification permission sheet.
    var showNotificationOnboarding = false

    /// Bumps on each `onAuthStateReady` so overlapping login callbacks cannot finish out of order.
    private var authReadyGeneration = 0
    private var authReadyTask: Task<Void, Never>?
    /// Distinguishes the latest bootstrap task so a superseded await does not clear a newer one.
    private var authReadyTaskID = 0

    func configure() {
        let ok = FirebaseBootstrap.configureIfNeeded()
        firebaseBootFailed = !ok
        guard ok else { return }
        authService.start()
        notificationService.start()
        appTheme.sync(from: authService.currentUser)
    }

    func bootstrapSession() async {
        #if DEBUG
        if DevAuthBypass.isEnabled {
            AppEvents.track(.sessionBootstrapStarted, metadata: ["mode": "dev_bypass"])
            await authService.activateDevBypass()
            await onAuthStateReady()
            return
        }
        #endif

        guard !firebaseBootFailed else {
            AppEvents.track(.sessionBootstrapFailed, metadata: ["reason": "firebase_boot_failed"])
            return
        }

        guard authService.authStateDetermined, authService.isAuthenticated else {
            AppEvents.track(.sessionBootstrapSkipped, metadata: [
                "auth_determined": authService.authStateDetermined ? "true" : "false",
                "signed_in": authService.isSignedIn ? "true" : "false",
            ])
            return
        }
        AppEvents.track(.sessionBootstrapStarted, metadata: ["mode": "persisted"])
        await onAuthStateReady()
    }

    func onAuthStateReady() async {
        // Cancel any in-flight bootstrap so a newer sign-in/out identity is not skipped
        // after awaiting a stale task (coalesce-and-return left sessions half-loaded).
        authReadyTask?.cancel()
        authReadyTaskID += 1
        let taskID = authReadyTaskID
        let task = Task { @MainActor in
            await performAuthStateReady()
        }
        authReadyTask = task
        await task.value
        if taskID == authReadyTaskID {
            authReadyTask = nil
        }
    }

    private func performAuthStateReady() async {
        guard !Task.isCancelled else { return }
        authReadyGeneration += 1
        let generation = authReadyGeneration
        CrashReport.breadcrumb("session.on_auth_ready_begin", metadata: [
            "gen": "\(generation)",
            "signed_in": authService.isSignedIn ? "true" : "false",
            "uid": AppEvents.shortUID(authService.currentUserId),
        ])

        guard let userId = authService.currentUserId else {
            AppLog.notice(AppLog.session, "onAuthStateReady aborted — missing userId", metadata: [
                "signed_in": authService.isSignedIn ? "true" : "false",
                "has_profile": authService.currentUser != nil ? "true" : "false",
                "gen": "\(generation)",
            ])
            return
        }

        if authService.currentUser == nil {
            AppLog.info(AppLog.session, "refreshing profile before session ready", metadata: [
                "uid": AppEvents.shortUID(userId),
                "gen": "\(generation)",
            ])
            await authService.refreshSession()
        }

        guard generation == authReadyGeneration else {
            AppLog.info(AppLog.session, "onAuthStateReady superseded after profile refresh", metadata: [
                "gen": "\(generation)",
                "current_gen": "\(authReadyGeneration)",
            ])
            return
        }

        appTheme.sync(from: authService.currentUser)
        groupService.loadGroups(for: userId)
        CrashReport.setUserID(userId)
        CrashReport.setValue(needsOnboarding ? "true" : "false", forKey: "needs_onboarding")
        CrashReport.setValue(authService.currentUser?.favoriteTeamId ?? "none", forKey: "favorite_team_id")
        AppEvents.track(.sessionBootstrapReady, metadata: [
            "uid": AppEvents.shortUID(userId),
            "needs_onboarding": needsOnboarding ? "true" : "false",
            "has_favorite_team": authService.currentUser?.favoriteTeamId != nil ? "true" : "false",
            "gen": "\(generation)",
        ])

        // Defer so RootView can leave onboarding and any auth sheets can dismiss first.
        scheduleFavoriteTeamPrompt()
        scheduleNotificationOnboarding()

        guard generation == authReadyGeneration else {
            AppLog.info(AppLog.session, "onAuthStateReady superseded after notifications", metadata: [
                "gen": "\(generation)",
                "current_gen": "\(authReadyGeneration)",
            ])
            return
        }

        await notificationService.saveToken(for: userId)
        CrashReport.breadcrumb("session.on_auth_ready_complete", metadata: [
            "gen": "\(generation)",
            "uid": AppEvents.shortUID(userId),
        ])
    }

    func scheduleNotificationOnboarding() {
        Task { @MainActor in
            await notificationService.refreshAuthorizationStatus()
            guard notificationService.authorizationStatus == .notDetermined else {
                if let userId = currentUserId {
                    await notificationService.saveToken(for: userId)
                }
                return
            }
            guard let userId = currentUserId else { return }
            guard !authService.hasDismissedNotificationOnboarding(for: userId) else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !needsOnboarding else { return }
            showNotificationOnboarding = true
        }
    }

    func handleDeepLink(_ action: DeepLinkAction) {
        AppLog.info(AppLog.session, "deep link", metadata: ["action": "\(action)"])
        switch action {
        case .joinGroup(let code):
            pendingInviteCode = code
            if authService.isAuthenticated {
                showJoinGroupSheet = true
            }
        case .openPickems(let groupId), .openLiveSlate(let groupId):
            selectDeepLinkGroup(groupId)
            selectedTab = .pickems
        case .openSelections(let groupId):
            selectDeepLinkGroup(groupId)
            selectedTab = .selections
        case .openLeagues(let groupId):
            selectDeepLinkGroup(groupId)
            selectedTab = .leagues
        case .openHome:
            selectedTab = .home
        case .openDiscover:
            selectedTab = .leagues
        case .openSelectionDeadline(let groupId):
            selectDeepLinkGroup(groupId)
            pendingSelectionDeadlinePrompt = true
            selectedTab = .selections
        }
    }

    private func selectDeepLinkGroup(_ groupId: String?) {
        pendingDeepLinkGroupId = groupId
        guard let groupId else { return }
        groupService.selectGroup(id: groupId)
    }

    func processPendingInviteIfNeeded() {
        guard pendingInviteCode != nil, authService.isAuthenticated else { return }
        showJoinGroupSheet = true
    }

    func resetSession() {
        groupService.resetSession()
        pickService.resetSession()
        picksViewModel.resetForSession()
        chatService.stopObserving()
    }
}

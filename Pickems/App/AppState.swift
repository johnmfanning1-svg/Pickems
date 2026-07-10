import Foundation
import FirebaseCore
import FirebaseFirestore

enum AppTab: Hashable {
    case home
    case groups
    case picks
    case profile
}

@MainActor
@Observable
final class AppState {
    let authService = AuthService()
    let groupService = GroupService()
    let pickService = PickService()
    let notificationService = NotificationService()
    let appTheme = AppTheme()

    var selectedTab: AppTab = .home
    var pendingInviteCode: String?
    var showJoinGroupSheet = false
    var showFavoriteTeamPicker = false

    /// Bumps on each `onAuthStateReady` so overlapping login callbacks cannot finish out of order.
    private var authReadyGeneration = 0

    func configure() {
        FirebaseBootstrap.configureIfNeeded()
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
        await notificationService.requestPermission()

        guard generation == authReadyGeneration else {
            AppLog.info(AppLog.session, "onAuthStateReady superseded after notifications", metadata: [
                "gen": "\(generation)",
                "current_gen": "\(authReadyGeneration)",
            ])
            return
        }

        await notificationService.saveToken(for: userId)
        processPendingInviteIfNeeded()
        CrashReport.breadcrumb("session.on_auth_ready_complete", metadata: [
            "gen": "\(generation)",
            "uid": AppEvents.shortUID(userId),
        ])
    }

    func handleDeepLink(_ action: DeepLinkAction) {
        AppLog.info(AppLog.session, "deep link", metadata: ["action": "\(action)"])
        switch action {
        case .joinGroup(let code):
            pendingInviteCode = code
            if authService.isAuthenticated {
                showJoinGroupSheet = true
            }
        case .openPicks, .openLiveSlate:
            selectedTab = .picks
        case .openGroups, .openDiscover:
            selectedTab = .groups
        case .openHome:
            selectedTab = .home
        }
    }

    func processPendingInviteIfNeeded() {
        guard pendingInviteCode != nil, authService.isAuthenticated else { return }
        showJoinGroupSheet = true
    }
}

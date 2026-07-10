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
        guard let userId = authService.currentUserId else {
            AppLog.notice(AppLog.session, "onAuthStateReady aborted — missing userId", metadata: [
                "signed_in": authService.isSignedIn ? "true" : "false",
                "has_profile": authService.currentUser != nil ? "true" : "false",
            ])
            return
        }
        if authService.currentUser == nil {
            AppLog.info(AppLog.session, "refreshing profile before session ready", metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
            await authService.refreshSession()
        }
        appTheme.sync(from: authService.currentUser)
        groupService.loadGroups(for: userId)
        CrashReport.setValue(needsOnboarding ? "true" : "false", forKey: "needs_onboarding")
        AppEvents.track(.sessionBootstrapReady, metadata: [
            "uid": AppEvents.shortUID(userId),
            "needs_onboarding": needsOnboarding ? "true" : "false",
            "has_favorite_team": authService.currentUser?.favoriteTeamId != nil ? "true" : "false",
        ])
        // Defer so RootView can leave onboarding and any auth sheets can dismiss first.
        scheduleFavoriteTeamPrompt()
        await notificationService.requestPermission()
        await notificationService.saveToken(for: userId)
        processPendingInviteIfNeeded()
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

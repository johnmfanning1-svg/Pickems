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

    var selectedTab: AppTab = .home
    var pendingInviteCode: String?
    var showJoinGroupSheet = false

    func configure() {
        FirebaseBootstrap.configureIfNeeded()
        PickemsTheme.apply()
    }

    func bootstrapSession() async {
        #if DEBUG
        if DevAuthBypass.isEnabled {
            await authService.activateDevBypass()
            await onAuthStateReady()
            return
        }
        #endif

        guard authService.authStateDetermined, authService.isAuthenticated else { return }
        await onAuthStateReady()
    }

    func onAuthStateReady() async {
        guard let userId = authService.currentUserId else { return }
        if authService.currentUser == nil {
            await authService.refreshSession()
        }
        groupService.loadGroups(for: userId)
        await notificationService.requestPermission()
        await notificationService.saveToken(for: userId)
        processPendingInviteIfNeeded()
    }

    func handleDeepLink(_ action: DeepLinkAction) {
        switch action {
        case .joinGroup(let code):
            pendingInviteCode = code
            if authService.isAuthenticated {
                showJoinGroupSheet = true
            }
        case .openPicks:
            selectedTab = .picks
        case .openGroups:
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

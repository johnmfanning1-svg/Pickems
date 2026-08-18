import SwiftUI
import FirebaseCore

@main
struct PickemsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState: AppState

    init() {
        // Idempotent with AppDelegate — whichever runs first wins. Must precede AppState
        // service startup (Auth listener / Messaging delegate).
        _ = FirebaseBootstrap.configureIfNeeded()
        let state = AppState()
        state.configure()
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        WindowGroup {
            SharingBootstrap {
                RootView()
                    .environment(appState)
                    .environment(\.themePalette, appState.appTheme.palette)
                    .onAppear {
                        appDelegate.setDeepLinkHandler { action in
                            appState.handleDeepLink(action)
                        }
                    }
                    .task {
                        appState.configure()
                        await appState.bootstrapSession()
                    }
                    .onChange(of: appState.authService.currentUser?.favoriteTeamId) { _, _ in
                        appState.appTheme.sync(from: appState.authService.currentUser)
                    }
                    .onOpenURL { url in
                        if let action = DeepLinkRouter.parse(url: url) {
                            appState.handleDeepLink(action)
                        }
                    }
                    .onChange(of: appState.authService.authStateDetermined) { _, determined in
                        #if DEBUG
                        guard !DevAuthBypass.isEnabled else { return }
                        #endif
                        guard determined, appState.authService.isAuthenticated else { return }
                        Task { await appState.onAuthStateReady() }
                    }
                    .onChange(of: appState.authService.isSignedIn) { _, signedIn in
                        #if DEBUG
                        guard !DevAuthBypass.isEnabled else { return }
                        #endif
                        guard signedIn else {
                            appState.resetSession()
                            return
                        }
                        Task { await appState.onAuthStateReady() }
                    }
                    .onChange(of: appState.needsOnboarding) { wasOnboarding, needsOnboarding in
                        if wasOnboarding, !needsOnboarding {
                            appState.selectedTab = .home
                            appState.scheduleFavoriteTeamPrompt()
                        }
                    }
                    .sheet(isPresented: Binding(
                        get: { appState.showJoinGroupSheet && !appState.liveConfig.requiresUpdate },
                        set: { appState.showJoinGroupSheet = $0 }
                    )) {
                        JoinGroupSheet(initialCode: appState.pendingInviteCode ?? "")
                            .pickemsEnvironment(appState)
                    }
                    .sheet(isPresented: Binding(
                        get: { appState.showFavoriteTeamPicker && !appState.liveConfig.requiresUpdate },
                        set: { appState.showFavoriteTeamPicker = $0 }
                    )) {
                        FavoriteTeamPickerView(isOnboardingPrompt: true)
                            .pickemsEnvironment(appState)
                    }
            }
        }
    }
}

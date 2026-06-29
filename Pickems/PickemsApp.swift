import SwiftUI
import FirebaseCore

@main
struct PickemsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState: AppState

    init() {
        FirebaseBootstrap.configureIfNeeded()
        _appState = State(initialValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            SharingBootstrap {
                RootView()
                    .environment(appState)
                    .task {
                        appState.configure()
                        appDelegate.onDeepLink = { [appState] action in
                            appState.handleDeepLink(action)
                        }
                        await appState.bootstrapSession()
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
                    .sheet(isPresented: Binding(
                        get: { appState.showJoinGroupSheet },
                        set: { appState.showJoinGroupSheet = $0 }
                    )) {
                        JoinGroupSheet(initialCode: appState.pendingInviteCode ?? "")
                    }
            }
        }
    }
}

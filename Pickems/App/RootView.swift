import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appState.firebaseBootFailed {
                bootFailureView
            } else {
                let config = appState.liveConfig
                if config.requiresUpdate {
                    ForceUpdateView()
                } else {
                    destinationContent
                }
            }
        }
        .preferredColorScheme(.dark)
        .background(PickemsAtmosphericBackground(palette: theme))
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await syncPushRegistration() }
        }
    }

    private func syncPushRegistration() async {
        if let uid = appState.currentUserId {
            await appState.notificationService.saveToken(for: uid)
        } else {
            await appState.notificationService.syncWithSystem()
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        // Touch observable auth/onboarding fields so SwiftUI leaves SignInView after login.
        let destination = authDestination
        Group {
            switch destination {
            case .loading:
                loadingView("Loading your league…")
            case .signIn:
                #if DEBUG
                if DevAuthBypass.isEnabled {
                    loadingView("Starting dev session…")
                } else {
                    SignInView()
                }
                #else
                SignInView()
                #endif
            case .onboarding:
                OnboardingView()
            case .main:
                MainTabView()
            }
        }
        .onChange(of: destination) { previous, next in
            AppEvents.track(.rootDestinationChanged, metadata: [
                "from": "\(previous)",
                "to": "\(next)",
                "signed_in": appState.authService.isSignedIn ? "true" : "false",
                "needs_onboarding": appState.needsOnboarding ? "true" : "false",
            ])
        }
    }

    private var bootFailureView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(PickemsColors.warning)
            Text("Pickems couldn’t start")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
            Text("Firebase configuration is missing from this build. Delete the app, reinstall from TestFlight, and try again.")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PickemsAtmosphericBackground(palette: theme))
    }

    private var authDestination: AuthRootDestination {
        #if DEBUG
        if DevAuthBypass.isEnabled {
            if !appState.authService.authStateDetermined {
                return .loading
            }
            if !appState.groupService.hasCompletedInitialGroupLoad {
                return .loading
            }
            return AuthRouting.destination(
                authStateDetermined: true,
                isAuthenticated: true,
                needsOnboarding: appState.needsOnboarding
            )
        }
        #endif
        // Explicit reads keep nested @Observable dependencies tracked.
        _ = appState.authService.isSignedIn
        _ = appState.authService.onboardingRevision
        _ = appState.authService.currentUser?.id
        _ = appState.groupService.groups.count
        _ = appState.groupService.selectedGroup?.id
        _ = appState.groupService.hasCompletedInitialGroupLoad

        let authenticated = appState.authService.isAuthenticated
        let determined = appState.authService.authStateDetermined
        if determined, authenticated, !appState.groupService.hasCompletedInitialGroupLoad {
            // Must not flicker this flag after the first snapshot — swapping away
            // from `.main` unmounts every tab (sheets are hosted above RootView).
            return .loading
        }

        return AuthRouting.destination(
            authStateDetermined: determined,
            isAuthenticated: authenticated,
            needsOnboarding: appState.needsOnboarding
        )
    }

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(theme.accent)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PickemsAtmosphericBackground(palette: theme))
    }
}

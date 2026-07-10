import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    var body: some View {
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
        .preferredColorScheme(.dark)
        .background(PickemsAtmosphericBackground(palette: theme))
        .onChange(of: destination) { previous, next in
            AppEvents.track(.rootDestinationChanged, metadata: [
                "from": "\(previous)",
                "to": "\(next)",
                "signed_in": appState.authService.isSignedIn ? "true" : "false",
                "needs_onboarding": appState.needsOnboarding ? "true" : "false",
            ])
        }
    }

    private var authDestination: AuthRootDestination {
        #if DEBUG
        if DevAuthBypass.isEnabled {
            if !appState.authService.authStateDetermined {
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

        return AuthRouting.destination(
            authStateDetermined: appState.authService.authStateDetermined,
            isAuthenticated: appState.authService.isAuthenticated,
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

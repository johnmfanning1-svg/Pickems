import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    var body: some View {
        Group {
            #if DEBUG
            if DevAuthBypass.isEnabled {
                devBypassRoot
            } else {
                productionAuthRoot
            }
            #else
            productionAuthRoot
            #endif
        }
        .preferredColorScheme(.dark)
        .background(PickemsAtmosphericBackground(palette: theme))
    }

    @ViewBuilder
    private var devBypassRoot: some View {
        if !appState.authService.authStateDetermined {
            loadingView("Starting dev session…")
        } else if appState.needsOnboarding {
            OnboardingView()
        } else {
            MainTabView()
        }
    }

    @ViewBuilder
    private var productionAuthRoot: some View {
        if !appState.authService.authStateDetermined {
            loadingView("Loading your league…")
        } else if appState.authService.isAuthenticated {
            if appState.needsOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        } else {
            SignInView()
        }
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

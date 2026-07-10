import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var showAdminLogin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "football.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(theme.accent)
                    Text("Pickems")
                        .font(.largeTitle.bold())
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text("College football picks with your crew")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .padding(.top, 40)

                Text("Sign in once with Apple — you'll stay signed in.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = appState.authService.prepareAppleSignIn()
                } onCompletion: { result in
                    Task {
                        switch result {
                        case .success(let authorization):
                            try? await appState.authService.signInWithApple(authorization: authorization)
                            await appState.onAuthStateReady()
                        case .failure(let error):
                            appState.authService.errorMessage = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                if appState.authService.isLoading {
                    ProgressView()
                        .tint(theme.accent)
                }

                if let error = appState.authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                #if DEBUG
                Button("Admin") {
                    showAdminLogin = true
                }
                .font(.caption2)
                .foregroundStyle(PickemsColors.textSecondary.opacity(0.5))
                .padding(.top, 24)
                #endif
            }
            .padding()
        }
        .background(PickemsColors.background)
        #if DEBUG
        .sheet(isPresented: $showAdminLogin) {
            AdminLoginSheet()
        }
        #endif
    }
}

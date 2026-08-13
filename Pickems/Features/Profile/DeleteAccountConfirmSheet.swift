import SwiftUI
import AuthenticationServices

/// Re-authenticates, then deletes the account. Firebase requires a recent login
/// before `User.delete()` — without this, deletion silently fails and the session remains.
struct DeleteAccountConfirmSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var auth: AuthService { appState.authService }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Confirm account deletion")
                        .font(.title2.bold())
                        .foregroundStyle(PickemsColors.textPrimary)

                    Text("For security, confirm it’s you. This permanently deletes your profile, avatar, and league memberships.")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)

                    if auth.hasPasswordProvider {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PickemsColors.textSecondary)
                            SecureField("Account password", text: $password)
                                .textFieldStyle(.pickems)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                        }

                        PrimaryButton(
                            title: "Delete Account",
                            isLoading: isWorking,
                            accessibilityHint: "Re-enter your password and permanently delete your account"
                        ) {
                            Task { await deleteWithPassword() }
                        }
                        .disabled(password.isEmpty || isWorking)
                    }

                    if auth.hasAppleProvider {
                        if auth.hasPasswordProvider {
                            Text("Or confirm with Apple")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                                .frame(maxWidth: .infinity)
                        }

                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = []
                            request.nonce = auth.prepareAppleSignIn()
                        } onCompletion: { result in
                            Task { await deleteWithApple(result) }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(isWorking)
                        .accessibilityHint("Confirm with Sign in with Apple, then permanently delete your account")
                    }

                    if !auth.hasPasswordProvider && !auth.hasAppleProvider {
                        Text("Sign out, sign back in, then try Delete Account again.")
                            .font(.subheadline)
                            .foregroundStyle(PickemsColors.warning)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                    }

                    Button("Cancel") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .disabled(isWorking)
                }
                .padding()
            }
            .pickemsScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isWorking)
                }
            }
        }
    }

    private func deleteWithPassword() async {
        await runDeletion {
            try await auth.reauthenticateWithPassword(password)
        }
    }

    private func deleteWithApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            await runDeletion {
                try await auth.reauthenticateWithApple(authorization: authorization)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func runDeletion(_ reauthenticate: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await reauthenticate()
            if let userId = auth.currentUserId {
                try await appState.groupService.leaveAllGroupsForAccountDeletion(userId: userId)
            }
            try await auth.deleteAccount()
            appState.groupService.resetSession()
            PickemsHaptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            PickemsHaptics.warning()
        }
    }
}

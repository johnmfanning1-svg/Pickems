#if DEBUG
import SwiftUI

struct AdminLoginSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme
    @State private var gatePassword = ""
    @State private var email = DevAdminConfig.defaultEmail
    @State private var firebasePassword = DevAdminConfig.defaultFirebasePassword
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Dev admin uses Firebase Email/Password. Enter the same email and password as in Firebase Console → Authentication → Users.")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)

                    Group {
                        Text("Gate password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                        SecureField("Gate password", text: $gatePassword)
                            .textFieldStyle(.pickems)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Group {
                        Text("Firebase email")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                        TextField("Email", text: $email)
                            .textFieldStyle(.pickems)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                    }

                    Group {
                        Text("Firebase password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                        SecureField("Password", text: $firebasePassword)
                            .textFieldStyle(.pickems)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    PrimaryButton(title: "Sign In", isLoading: appState.authService.isLoading) {
                        Task {
                            do {
                                try await appState.authService.signInAsAdmin(
                                    gatePassword: gatePassword,
                                    email: email,
                                    firebasePassword: firebasePassword
                                )
                                await appState.onAuthStateReady()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding()
            }
            .background(PickemsColors.background)
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
#endif

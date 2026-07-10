import SwiftUI

struct ForgotPasswordSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    @State private var email: String
    @State private var localError: String?
    @State private var didSend = false

    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Enter the email for your account and we'll send a reset link.")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)

                    Text("Email")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                    TextField("you@example.com", text: $email)
                        .textFieldStyle(.pickems)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .disabled(didSend)

                    if didSend {
                        Text("If an account exists for that email, a reset link is on the way. Check your inbox.")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }

                    PrimaryButton(
                        title: didSend ? "Done" : "Send Reset Link",
                        isLoading: appState.authService.isLoading && !didSend
                    ) {
                        if didSend {
                            dismiss()
                        } else {
                            Task { await sendReset() }
                        }
                    }

                    if let localError {
                        Text(localError)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding()
            }
            .background(PickemsColors.background)
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func sendReset() async {
        localError = nil
        do {
            try await appState.authService.sendPasswordReset(email: email)
            didSend = true
            PickemsHaptics.success()
        } catch {
            localError = error.localizedDescription
        }
    }
}

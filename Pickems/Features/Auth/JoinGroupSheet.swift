import SwiftUI

struct JoinGroupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    @State var initialCode: String
    @State private var inviteCode = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite Code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    HStack {
                        Text("Join a League")
                        Spacer()
                        HelpInfoButton(topic: PickemsHelp.joinGroup, size: .caption)
                    }
                } footer: {
                    Text("Enter the 6-character code from your commissioner.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(theme.accent)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { join() }
                        .fontWeight(.semibold)
                        .disabled(inviteCode.count != 6 || isWorking)
                }
            }
            .onAppear {
                if inviteCode.isEmpty { inviteCode = initialCode }
            }
        }
        .presentationDetents([.medium])
    }

    private func join() {
        Task {
            isWorking = true
            errorMessage = nil
            defer { isWorking = false }

            guard appState.authService.currentUser != nil else {
                errorMessage = "Sign in required."
                return
            }
            do {
                try await appState.joinGroup(inviteCode: inviteCode, markOnboarding: true)
                PickemsHaptics.success()
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error, context: .joinGroup)
                    ?? "Couldn't join that league. Check the invite code and try again."
            }
        }
    }
}

import SwiftUI

struct JoinGroupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    @State var initialCode: String
    @State private var inviteCode = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var path = NavigationPath()
    @State private var detent: PresentationDetent = .medium

    private enum JoinSheetRoute: Hashable {
        case browse
    }

    var body: some View {
        NavigationStack(path: $path) {
            joinForm
                .navigationTitle("Join League")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Join") { join() }
                            .fontWeight(.semibold)
                            .disabled(!InviteCodeRules.isValidFormat(inviteCode) || isWorking)
                    }
                }
                .navigationDestination(for: JoinSheetRoute.self) { _ in
                    PublicLeagueBrowseView { listing in
                        await join(listing: listing)
                    }
                }
                .onAppear {
                    if inviteCode.isEmpty { inviteCode = initialCode }
                }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: path.count) { _, count in
            detent = count == 0 ? .medium : .large
        }
    }

    private var joinForm: some View {
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
                Text("Enter the 4–8 character code from your commissioner.")
            }

            Section {
                NavigationLink(value: JoinSheetRoute.browse) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PublicLeagueBrowse.entryTitle)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(theme.accent)
                            Text(PublicLeagueBrowse.entrySubtitle)
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityLabel(PublicLeagueBrowse.accessibilityLabel)
                .accessibilityHint(PublicLeagueBrowse.accessibilityHint)
            } footer: {
                Text(PublicLeagueBrowse.entryFooter)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(theme.accent)
                        .font(.caption)
                }
            }
        }
    }

    private func join() {
        Task { _ = await join(code: inviteCode) }
    }

    private func join(listing: PublicLeagueListing) async -> String? {
        guard let code = PublicLeagueBrowse.joinCode(for: listing) else {
            let message = "Couldn't join that league. Try again."
            errorMessage = message
            return message
        }
        return await join(code: code)
    }

    /// Same open/join path the invite field uses. Returns a message, or nil
    /// after the sheet dismisses.
    @discardableResult
    private func join(code: String) async -> String? {
        guard !isWorking else { return nil }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        guard appState.authService.currentUser != nil else {
            let message = "Sign in required."
            errorMessage = message
            return message
        }
        do {
            try await appState.joinGroup(inviteCode: code, markOnboarding: true)
            PickemsHaptics.success()
            dismiss()
            return nil
        } catch {
            let message = UserFacingError.message(for: error, context: .joinGroup)
                ?? "Couldn't join that league. Check the invite code and try again."
            errorMessage = message
            return message
        }
    }
}

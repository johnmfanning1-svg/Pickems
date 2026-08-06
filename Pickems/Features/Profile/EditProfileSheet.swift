import SwiftUI

/// Dedicated editor for first name, last name, and username, presented as its own
/// sheet so saving is a single clear action instead of inline Form editing.
struct EditProfileSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var usernameAvailability: AuthService.UsernameAvailability?
    @State private var usernameCheckTask: Task<Void, Never>?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case firstName, lastName, username
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .firstName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .lastName }
                        .listRowBackground(PickemsColors.cardBackground)

                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .lastName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
                        .listRowBackground(PickemsColors.cardBackground)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Your first and last name are for your account.")
                }

                Section {
                    HStack {
                        Text("@")
                            .foregroundStyle(PickemsColors.textSecondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .focused($focusedField, equals: .username)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .onChange(of: username) { _, newValue in
                                errorMessage = nil
                                scheduleUsernameCheck(newValue)
                            }
                    }
                    .listRowBackground(PickemsColors.cardBackground)

                    usernameStatusRow
                        .listRowBackground(PickemsColors.cardBackground)
                } header: {
                    Text("Username")
                } footer: {
                    Text("Your username is unique and shown to everyone in your leagues (letters, numbers, underscore).")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving || !canSave)
                }
            }
            .onAppear(perform: loadFields)
            .onDisappear { usernameCheckTask?.cancel() }
        }
    }

    @ViewBuilder
    private var usernameStatusRow: some View {
        switch usernameAvailability {
        case .available:
            if isUsernameDirty {
                Label("Username is available", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.success)
            }
        case .taken:
            Label("Username is taken", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(PickemsColors.warning)
        case .invalid(let error):
            if isUsernameDirty {
                Text(error.localizedDescription ?? "Invalid username")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.warning)
            }
        case .none:
            if isUsernameDirty {
                Text("Checking availability…")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
    }

    // MARK: - Dirty / validation

    private var isUsernameDirty: Bool {
        let current = appState.authService.currentUser?.displayName ?? ""
        return DisplayNameRules.normalize(username) != DisplayNameRules.normalize(current)
    }

    private var isLegalNameDirty: Bool {
        let user = appState.authService.currentUser
        return PersonNameRules.normalize(firstName) != PersonNameRules.normalize(user?.firstName ?? "")
            || PersonNameRules.normalize(lastName) != PersonNameRules.normalize(user?.lastName ?? "")
    }

    private var isDirty: Bool { isUsernameDirty || isLegalNameDirty }

    private var canSave: Bool {
        guard case .success = PersonNameRules.validate(firstName, field: "first name"),
              case .success = PersonNameRules.validate(lastName, field: "last name") else {
            return false
        }
        guard isDirty else { return false }
        if isUsernameDirty {
            if case .available = usernameAvailability { return true }
            return false
        }
        return true
    }

    // MARK: - Actions

    private func loadFields() {
        guard let user = appState.authService.currentUser else { return }
        firstName = user.firstName ?? ""
        lastName = user.lastName ?? ""
        username = user.displayName
        usernameAvailability = nil
        errorMessage = nil
    }

    private func scheduleUsernameCheck(_ raw: String) {
        usernameCheckTask?.cancel()
        usernameAvailability = nil
        let trimmed = DisplayNameRules.normalize(raw)
        guard !trimmed.isEmpty, isUsernameDirty else { return }
        usernameCheckTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let result = await appState.authService.checkUsernameAvailability(trimmed)
            guard !Task.isCancelled else { return }
            usernameAvailability = result
        }
    }

    private func save() {
        focusedField = nil
        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }
            do {
                if isLegalNameDirty {
                    try await appState.authService.updateLegalName(firstName: firstName, lastName: lastName)
                }
                if isUsernameDirty {
                    try await appState.authService.updateDisplayName(username)
                    if let userId = appState.authService.currentUserId {
                        await appState.groupService.syncMemberDisplayName(
                            userId: userId,
                            displayName: DisplayNameRules.normalize(username)
                        )
                    }
                }
                PickemsHaptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }
}

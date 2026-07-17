import SwiftUI
import PhotosUI
import UserNotifications

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var isSavingProfile = false
    @State private var profileError: String?
    @State private var profileSavedMessage: String?
    @State private var usernameAvailability: AuthService.UsernameAvailability?
    @State private var usernameCheckTask: Task<Void, Never>?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var showJoinSheet = false
    @State private var showCreateWizard = false
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var showTeamPicker = false
    @State private var managementError: String?
    @State private var presentedHelp: HelpTopic?

    @FocusState private var focusedField: ProfileField?

    private enum ProfileField: Hashable {
        case firstName, lastName, username
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                favoriteTeamSection
                notificationsSection
                if AppConfig.isXSharingConfigured {
                    sharingSection
                }
                leaguesSection
                legalSection
                accountActionsSection
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HelpInfoButton(
                        topic: PickemsHelp.profileOverview,
                        presentedTopic: $presentedHelp
                    )
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
                if isProfileDirty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSavingProfile ? "Saving…" : "Save") {
                            saveProfile()
                        }
                        .disabled(isSavingProfile || !canSaveProfile)
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(item: $presentedHelp) { topic in
                HelpDetailView(topic: topic)
                    .environment(\.themePalette, theme)
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinGroupSheet(initialCode: "")
                    .pickemsEnvironment(appState)
            }
            .sheet(isPresented: $showCreateWizard) {
                CreateGroupWizardView()
                    .pickemsEnvironment(appState)
            }
            .sheet(isPresented: $showTeamPicker) {
                FavoriteTeamPickerView()
                    .pickemsEnvironment(appState)
            }
            .confirmationDialog("Leave this league?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
                Button("Leave League", role: .destructive) { leaveGroup() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this league permanently?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete League", role: .destructive) { deleteGroup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All members will lose access. This cannot be undone.")
            }
            .confirmationDialog("Sign out of Pickems?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { signOut() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete your Pickems account?",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your profile, avatar, and league memberships. This cannot be undone.")
            }
            .onChange(of: selectedPhoto) { _, item in
                uploadAvatar(from: item)
            }
            .onAppear {
                loadProfileFields()
                Task { await appState.notificationService.refreshAuthorizationStatus() }
            }
            .onChange(of: appState.authService.currentUser) { _, _ in
                if !isProfileDirty { loadProfileFields() }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            if let user = appState.authService.currentUser {
                HStack(spacing: 16) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        InitialsAvatar(
                            initials: user.initials,
                            colorHex: user.avatarColorHex,
                            imageURL: user.avatarImageURL,
                            size: 56
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.caption2)
                                .foregroundStyle(theme.onAccent)
                                .padding(4)
                                .background(theme.accent)
                                .clipShape(Circle())
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isUploadingAvatar)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.fullName ?? "Add your name")
                            .font(.headline)
                            .foregroundStyle(PickemsColors.textPrimary)
                        Text("@\(user.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(PickemsColors.textSecondary)
                        if isUploadingAvatar {
                            Text("Uploading photo…")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        } else {
                            Text("Tap photo to change")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                    }
                }
                .listRowBackground(PickemsColors.cardBackground)

                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .firstName)
                    .listRowBackground(PickemsColors.cardBackground)

                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .lastName)
                    .listRowBackground(PickemsColors.cardBackground)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("@")
                            .foregroundStyle(PickemsColors.textSecondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .focused($focusedField, equals: .username)
                            .onChange(of: username) { _, newValue in
                                profileError = nil
                                profileSavedMessage = nil
                                scheduleUsernameCheck(newValue)
                            }
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }

                    usernameStatusRow

                    if isProfileDirty {
                        Button {
                            focusedField = nil
                            saveProfile()
                        } label: {
                            HStack {
                                if isSavingProfile { ProgressView() }
                                Text(isSavingProfile ? "Saving…" : "Save profile")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isSavingProfile || !canSaveProfile)
                    }

                    if let profileError {
                        Text(profileError)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                    } else if let profileSavedMessage {
                        Text(profileSavedMessage)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.success)
                    }
                }
                .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("First and last name are for your account. Username is unique and shown in leagues (letters, numbers, underscore).")
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

    // MARK: - Team / Notifications / etc.

    private var favoriteTeamSection: some View {
        Section {
            Button {
                showTeamPicker = true
            } label: {
                HStack(spacing: 12) {
                    if let team = appState.authService.currentUser?.favoriteTeam {
                        ZStack {
                            Circle()
                                .fill(team.primaryColor)
                                .frame(width: 36, height: 36)
                            if let url = URL(string: team.resolvedLogoURL) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFit()
                                    }
                                }
                                .frame(width: 24, height: 24)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name)
                                .foregroundStyle(PickemsColors.textPrimary)
                            Text("Themes accents across Pickems")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                    } else {
                        Label("Choose Favorite Team", systemImage: "shield.lefthalf.filled")
                            .foregroundStyle(theme.accent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)
        } header: {
            Text("Team Theme")
        } footer: {
            Text("Your favorite team colors the app accents and atmosphere for you.")
        }
    }

    private var notificationsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Game & league alerts", systemImage: "bell.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)

                Text(notificationExplanation)
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                notificationActionControls
            }
            .listRowBackground(PickemsColors.cardBackground)
        } header: {
            HStack {
                Text("Notifications")
                Spacer()
                HelpInfoButton(
                    topic: PickemsHelp.notifications,
                    size: .body,
                    presentedTopic: $presentedHelp
                )
            }
        } footer: {
            Text(notificationFooter)
        }
    }

    @ViewBuilder
    private var notificationActionControls: some View {
        switch appState.notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            HStack {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(PickemsColors.success)
                Spacer()
                Button("Open Settings") {
                    appState.notificationService.openSystemSettings()
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
            }
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label("Off — blocked in iOS Settings", systemImage: "bell.slash.fill")
                    .foregroundStyle(PickemsColors.warning)
                Button {
                    appState.notificationService.openSystemSettings()
                } label: {
                    Text("Enable in Settings")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
        case .notDetermined:
            Button {
                Task { await appState.notificationService.requestPermission() }
            } label: {
                Text("Allow notifications")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
        @unknown default:
            Button("Refresh status") {
                Task { await appState.notificationService.refreshAuthorizationStatus() }
            }
            .buttonStyle(.borderless)
        }
    }

    private var notificationExplanation: String {
        "Pickems can alert you when pick deadlines are approaching and when your week is scored. We do not send marketing spam."
    }

    private var notificationFooter: String {
        switch appState.notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "To turn alerts off, use Open Settings → Notifications."
        case .denied:
            return "iOS blocked alerts for Pickems. Use Enable in Settings to change that."
        default:
            return "You’ll get an iOS permission prompt when you tap Allow notifications."
        }
    }

    private var sharingSection: some View {
        Section {
            NavigationLink {
                XConnectionSettingsView()
            } label: {
                Label("X (Twitter) Account", systemImage: "link")
            }
            .listRowBackground(PickemsColors.cardBackground)

            if let shareSource = appState.seasonShareSource() {
                ShareResultsButton(source: shareSource)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("Sharing")
        }
    }

    private var leaguesSection: some View {
        Section {
            Button {
                showJoinSheet = true
            } label: {
                Label("Join Another League", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)

            Button {
                showCreateWizard = true
            } label: {
                Label("Create New League", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)

            if let group = appState.groupService.selectedGroup {
                LabeledContent("Current Group", value: group.name)
                    .listRowBackground(PickemsColors.cardBackground)
                LabeledContent("Invite Code", value: group.inviteCode)
                    .listRowBackground(PickemsColors.cardBackground)

                InviteShareButton(group: group)
                    .listRowBackground(PickemsColors.cardBackground)

                if appState.isCommissioner {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete League", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .listRowBackground(PickemsColors.cardBackground)
                } else {
                    Button(role: .destructive) {
                        showLeaveConfirm = true
                    } label: {
                        Label("Leave League", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.borderless)
                    .listRowBackground(PickemsColors.cardBackground)
                }
            }

            if let managementError {
                Text(managementError)
                    .font(.caption)
                    .foregroundStyle(theme.accent)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            HStack {
                Text("Leagues")
                Spacer()
                HelpInfoButton(
                    topic: PickemsHelp.inviteFriends,
                    size: .body,
                    presentedTopic: $presentedHelp
                )
            }
        }
    }

    private var legalSection: some View {
        Section {
            if let privacyURL = AppConfig.privacyPolicyURL {
                Link(destination: privacyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
                .listRowBackground(PickemsColors.cardBackground)
            }
            if let termsURL = AppConfig.termsOfServiceURL {
                Link(destination: termsURL) {
                    Label("Terms of Service", systemImage: "doc.text.fill")
                }
                .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("Legal")
        }
    }

    private var accountActionsSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)
            .disabled(isDeletingAccount)

            Button(role: .destructive) {
                showDeleteAccountConfirm = true
            } label: {
                if isDeletingAccount {
                    HStack {
                        ProgressView()
                        Text("Deleting Account…")
                    }
                } else {
                    Label("Delete Account", systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)
            .disabled(isDeletingAccount)
        } footer: {
            Text("Deleting your account permanently removes your profile, avatar, and league memberships.")
        }
    }

    // MARK: - Profile save helpers

    private var isUsernameDirty: Bool {
        let current = appState.authService.currentUser?.displayName ?? ""
        return DisplayNameRules.normalize(username) != DisplayNameRules.normalize(current)
    }

    private var isLegalNameDirty: Bool {
        let user = appState.authService.currentUser
        return PersonNameRules.normalize(firstName) != PersonNameRules.normalize(user?.firstName ?? "")
            || PersonNameRules.normalize(lastName) != PersonNameRules.normalize(user?.lastName ?? "")
    }

    private var isProfileDirty: Bool {
        isUsernameDirty || isLegalNameDirty
    }

    private var canSaveProfile: Bool {
        guard case .success = PersonNameRules.validate(firstName, field: "first name"),
              case .success = PersonNameRules.validate(lastName, field: "last name") else {
            return false
        }
        if isUsernameDirty {
            if case .available = usernameAvailability { return true }
            return false
        }
        return isLegalNameDirty
    }

    private func loadProfileFields() {
        guard let user = appState.authService.currentUser else { return }
        firstName = user.firstName ?? ""
        lastName = user.lastName ?? ""
        username = user.displayName
        profileError = nil
        profileSavedMessage = nil
        usernameAvailability = nil
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

    private func saveProfile() {
        Task {
            isSavingProfile = true
            profileError = nil
            profileSavedMessage = nil
            defer { isSavingProfile = false }
            do {
                if isLegalNameDirty {
                    try await appState.authService.updateLegalName(
                        firstName: firstName,
                        lastName: lastName
                    )
                }
                if isUsernameDirty {
                    try await appState.authService.updateDisplayName(username)
                    if let userId = appState.authService.currentUserId {
                        await appState.groupService.syncMemberDisplayName(
                            userId: userId,
                            displayName: DisplayNameRules.normalize(username)
                        )
                    }
                    username = DisplayNameRules.normalize(username)
                }
                firstName = PersonNameRules.normalize(firstName)
                lastName = PersonNameRules.normalize(lastName)
                usernameAvailability = nil
                profileSavedMessage = "Profile saved."
                focusedField = nil
                PickemsHaptics.success()
            } catch {
                profileError = error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func uploadAvatar(from item: PhotosPickerItem?) {
        guard let item,
              let userId = appState.authService.currentUser?.id else { return }
        Task {
            isUploadingAvatar = true
            defer { isUploadingAvatar = false }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            do {
                let url = try await AvatarService.uploadAvatar(userId: userId, image: image)
                try await appState.authService.updateAvatarURL(url)
                PickemsHaptics.success()
            } catch {
                managementError = error.localizedDescription
            }
        }
    }

    private func leaveGroup() {
        guard let group = appState.groupService.selectedGroup,
              let userId = appState.authService.currentUser?.id else { return }
        Task {
            do {
                try await appState.groupService.leaveGroup(groupId: group.id, userId: userId)
                PickemsHaptics.success()
            } catch {
                managementError = error.localizedDescription
            }
        }
    }

    private func deleteGroup() {
        guard let group = appState.groupService.selectedGroup else { return }
        Task {
            do {
                try await appState.groupService.deleteGroup(groupId: group.id)
                PickemsHaptics.success()
            } catch {
                managementError = error.localizedDescription
            }
        }
    }

    private func signOut() {
        do {
            try appState.authService.signOut()
        } catch {
            managementError = error.localizedDescription
        }
    }

    private func deleteAccount() {
        Task {
            isDeletingAccount = true
            defer { isDeletingAccount = false }
            do {
                let groups = appState.groupService.groups
                if let userId = appState.authService.currentUserId {
                    for group in groups {
                        try await appState.groupService.leaveGroup(groupId: group.id, userId: userId)
                    }
                }
                try await appState.authService.deleteAccount()
                PickemsHaptics.success()
            } catch {
                managementError = error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }
}

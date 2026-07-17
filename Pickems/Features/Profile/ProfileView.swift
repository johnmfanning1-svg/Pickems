import SwiftUI
import PhotosUI
import UserNotifications

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var showEditProfile = false
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
                        alignment: .center,
                        presentedTopic: $presentedHelp
                    )
                }
            }
            .sheet(item: $presentedHelp) { topic in
                HelpDetailView(topic: topic)
                    .environment(\.themePalette, theme)
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileSheet()
                    .pickemsEnvironment(appState)
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
                Task { await appState.notificationService.refreshAuthorizationStatus() }
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

                Button {
                    showEditProfile = true
                } label: {
                    HStack {
                        Label("Edit Name & Username", systemImage: "pencil")
                            .foregroundStyle(theme.accent)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                }
                .buttonStyle(.borderless)
                .listRowBackground(PickemsColors.cardBackground)
                .accessibilityHint("Opens a sheet to edit your first name, last name, and username")
            }
        } header: {
            Text("Account")
        } footer: {
            Text("First and last name are for your account. Username is unique and shown in leagues.")
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

    // MARK: - Profile helpers

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

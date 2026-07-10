import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var displayName = ""
    @State private var didSave = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var showJoinSheet = false
    @State private var showCreateWizard = false
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showSignOutConfirm = false
    @State private var showTeamPicker = false
    @State private var managementError: String?

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                favoriteTeamSection
                notificationsSection
                sharingSection
                leaguesSection
                saveSection
                accountActionsSection
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HelpToolbarButton(topic: PickemsHelp.profileOverview)
                }
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinGroupSheet(initialCode: "")
            }
            .sheet(isPresented: $showCreateWizard) {
                CreateGroupWizardView()
            }
            .sheet(isPresented: $showTeamPicker) {
                FavoriteTeamPickerView()
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
            .onChange(of: selectedPhoto) { _, item in
                uploadAvatar(from: item)
            }
        }
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 16) {
                if let user = appState.authService.currentUser {
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
                                .padding(4)
                                .background(theme.accent)
                                .clipShape(Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploadingAvatar)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Display Name", text: $displayName)
                            .onAppear { displayName = user.displayName }
                        if isUploadingAvatar {
                            Text("Uploading photo…")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        } else {
                            Text("Tap avatar to upload a photo")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                    }
                }
            }
            .listRowBackground(PickemsColors.cardBackground)
        } header: {
            Text("Account")
        }
    }

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
            .listRowBackground(PickemsColors.cardBackground)
        } header: {
            Text("Team Theme")
        } footer: {
            Text("Your favorite team colors the app accents and atmosphere for you.")
        }
    }

    private var notificationsSection: some View {
        Section {
            LabeledContent {
                Text(appState.notificationService.isAuthorized ? "On" : "Off")
                    .foregroundStyle(
                        appState.notificationService.isAuthorized
                            ? PickemsColors.success
                            : PickemsColors.textSecondary
                    )
            } label: {
                Label("Push Notifications", systemImage: "bell.fill")
            }
            .listRowBackground(PickemsColors.cardBackground)

            if !appState.notificationService.isAuthorized {
                Button {
                    Task { await appState.notificationService.requestPermission() }
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                }
                .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            HStack {
                Text("Notifications")
                Spacer()
                HelpInfoButton(topic: PickemsHelp.notifications, size: .caption)
            }
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
            .listRowBackground(PickemsColors.cardBackground)

            Button {
                showCreateWizard = true
            } label: {
                Label("Create New League", systemImage: "plus.circle")
            }
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
                    .listRowBackground(PickemsColors.cardBackground)
                } else {
                    Button(role: .destructive) {
                        showLeaveConfirm = true
                    } label: {
                        Label("Leave League", systemImage: "rectangle.portrait.and.arrow.right")
                    }
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
                HelpInfoButton(topic: PickemsHelp.inviteFriends, size: .caption)
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                Task {
                    try? await appState.authService.updateDisplayName(displayName)
                    PickemsHaptics.success()
                    didSave = true
                }
            } label: {
                HStack {
                    Text("Save Display Name")
                    Spacer()
                    if didSave {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PickemsColors.success)
                    }
                }
            }
            .listRowBackground(PickemsColors.cardBackground)
        }
    }

    private var accountActionsSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .listRowBackground(PickemsColors.cardBackground)
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
}

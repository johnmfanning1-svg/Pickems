import SwiftUI
import PhotosUI
import UserNotifications

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var showLeaveConfirm = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var managementError: String?
    @State private var isRefreshing = false
    @State private var showScrimmage = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                notificationsSection
                if AppConfig.isXSharingConfigured {
                    sharingSection
                }
                leaguesSection
                if !appState.groupService.groups.isEmpty {
                    widgetDisplaySection
                }
                howToPlaySection
                legalSection
                accountActionsSection
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .pickemsRefreshable(isRefreshing: $isRefreshing) {
                await appState.authService.refreshSession()
                await appState.refreshLeagueData()
                await syncNotificationRegistration()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            appState.present(.favoriteTeam(isOnboardingPrompt: false))
                        } label: {
                            teamThemeToolbarLabel
                        }
                        .accessibilityLabel("Team Theme")
                        .accessibilityHint("Opens favorite team picker to theme the app")

                        HelpInfoButton(
                            topic: PickemsHelp.profileOverview,
                            alignment: .center,
                            isToolbar: true
                        )
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .fullScreenCover(isPresented: $showScrimmage) {
                ScrimmageView(context: .replay)
                    .pickemsEnvironment(appState)
            }
            // Prefer `.alert` over `.confirmationDialog` on Profile: on iPad,
            // confirmationDialog presents as a popover and often anchors to the
            // top of the screen when attached to NavigationStack/Form.
            .alert("Leave this league?", isPresented: $showLeaveConfirm) {
                Button("Leave League", role: .destructive) { leaveGroup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You’ll lose access until you rejoin with the invite code.")
            }
            .alert("Sign out of Pickems?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) { signOut() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Delete your Pickems account?", isPresented: $showDeleteAccountConfirm) {
                Button("Continue", role: .destructive) { appState.present(.deleteAccount) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your profile, avatar, and league memberships. You’ll confirm your identity next. This cannot be undone.")
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { managementError != nil },
                set: { if !$0 { managementError = nil } }
            )) {
                Button("OK", role: .cancel) { managementError = nil }
            } message: {
                Text(managementError ?? "")
            }
            .onChange(of: selectedPhoto) { _, item in
                uploadAvatar(from: item)
            }
            .onAppear {
                Task { await syncNotificationRegistration() }
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
                    appState.present(.editProfile)
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

    // MARK: - Notifications / etc.

    @ViewBuilder
    private var teamThemeToolbarLabel: some View {
        Group {
            if let team = appState.authService.currentUser?.favoriteTeam,
               let url = URL(string: team.resolvedLogoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.callout)
                            .foregroundStyle(theme.accent)
                    }
                }
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.callout)
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(width: 22, height: 22)
        .frame(width: 30, height: 30)
        .contentShape(Rectangle().inset(by: -7))
        .accessibilityHidden(true)
    }

    private var notificationsSection: some View {
        Section {
            Button {
                appState.present(.notificationSettings)
            } label: {
                HStack {
                    Label("Notification settings", systemImage: "bell.badge")
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Text(notificationStatusCaption)
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)
            .accessibilityHint("Opens a sheet to choose which alerts you get")
        } header: {
            HStack {
                Text("Notifications")
                Spacer()
                HelpInfoButton(
                    topic: PickemsHelp.notifications,
                    size: .callout
                )
            }
        } footer: {
            Text(notificationFooter)
        }
    }

    private var notificationStatusCaption: String {
        switch appState.notificationService.authorizationStatus {
        case .denied:
            return "Off in iOS"
        case .notDetermined:
            return "Not enabled"
        case .authorized, .provisional, .ephemeral:
            let total = NotificationPrefCategory.allCases.count
            let onCount = appState.authService.currentUser?.enabledNotificationPrefCount ?? total
            if onCount == total { return "All on" }
            if onCount == 0 { return "All off" }
            return "\(onCount) of \(total) on"
        @unknown default:
            return "Settings"
        }
    }

    private var notificationFooter: String {
        switch appState.notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Choose which alerts you get. Turn iOS alerts off in Settings if you want none."
        case .denied:
            return "iOS blocked alerts for Pickems. Open Notification settings to enable them."
        default:
            return "Open Notification settings to allow alerts and choose which ones you get."
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
            if let group = appState.groupService.selectedGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(PickemsColors.textPrimary)
                    if group.canShareInvite(asCommissioner: appState.isCommissioner) {
                        Text("Invite code \(group.inviteCode)")
                            .font(.caption.monospaced())
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                }
                .listRowBackground(PickemsColors.cardBackground)

                if appState.groupService.groups.count > 1 {
                    Picker("Active league", selection: currentGroupSelection) {
                        ForEach(appState.groupService.groups) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                    .accessibilityHint("Switch which league is active")
                }

                if group.canShareInvite(asCommissioner: appState.isCommissioner) {
                    InviteShareButton(group: group)
                        .listRowBackground(PickemsColors.cardBackground)
                } else {
                    CommissionerOnlyInviteNotice(
                        commissionerName: appState.groupService.members
                            .first { $0.id == group.commissionerId }?.displayName
                    )
                    .listRowBackground(PickemsColors.cardBackground)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Button {
                appState.present(.joinGroup)
            } label: {
                Label("Join a League", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)

            Button {
                appState.present(.createLeague)
            } label: {
                Label("Create a League", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)

            if appState.groupService.selectedGroup != nil, !appState.isCommissioner {
                Button(role: .destructive) {
                    showLeaveConfirm = true
                } label: {
                    Label("Leave League", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            HStack {
                Text("Leagues")
                Spacer()
                HelpInfoButton(
                    topic: PickemsHelp.inviteFriends,
                    size: .callout
                )
            }
        }
    }

    private var widgetDisplaySection: some View {
        Section {
            Picker("League", selection: displayGroupSelection) {
                ForEach(appState.groupService.groups) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .listRowBackground(PickemsColors.cardBackground)
            .accessibilityHint("Choose which league the Home Screen widget and Live Activities show")
        } header: {
            HStack {
                Text("Home Screen & Live Activity")
                Spacer()
                HelpInfoButton(
                    topic: PickemsHelp.widgetAndLiveActivity,
                    size: .callout
                )
            }
        } footer: {
            Text("The widget and live lock screen / Dynamic Island follow this league, even if you switch leagues in the app.")
        }
    }

    private var howToPlaySection: some View {
        Section {
            Button {
                showScrimmage = true
            } label: {
                Label("Play a Scrimmage", systemImage: "figure.american.football")
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)
            .accessibilityHint("Opens a practice week that teaches Selections and Pickems")
        } header: {
            Text("How to Play")
        } footer: {
            Text("Practice Selections → Pickems with fake games. Results never count.")
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

            Button(role: .destructive) {
                showDeleteAccountConfirm = true
            } label: {
                Label("Delete Account", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)
        } footer: {
            Text("Deleting your account permanently removes your profile, avatar, and league memberships.")
        }
    }

    // MARK: - Profile helpers

    private var currentGroupSelection: Binding<String> {
        Binding(
            get: { appState.groupService.selectedGroup?.id ?? "" },
            set: { newId in
                guard let match = appState.groupService.groups.first(where: { $0.id == newId }) else { return }
                appState.groupService.selectGroup(match)
            }
        )
    }

    private var displayGroupSelection: Binding<String> {
        Binding(
            get: {
                WidgetSnapshotService.resolvedDisplayGroup(from: appState)?.id ?? ""
            },
            set: { newId in
                guard appState.groupService.groups.contains(where: { $0.id == newId }) else { return }
                PickemsAppGroup.setDisplayGroupId(newId)
                appState.publishSurfaces()
            }
        )
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
                await appState.groupService.syncMemberAvatarURL(userId: userId, avatarImageURL: url)
                PickemsHaptics.success()
            } catch {
                managementError = UserFacingError.message(for: error, context: .write) ?? "Something went wrong. Please try again."
            }
        }
    }

    private func leaveGroup() {
        guard let group = appState.groupService.selectedGroup,
              let userId = appState.authService.currentUser?.id else { return }
        Task {
            do {
                try await appState.groupService.leaveGroup(groupId: group.id, userId: userId)
                appState.publishSurfaces()
                PickemsHaptics.success()
            } catch {
                managementError = UserFacingError.message(for: error, context: .write) ?? "Something went wrong. Please try again."
            }
        }
    }

    private func signOut() {
        Task {
            do {
                try await appState.signOut()
                appState.publishSurfaces()
            } catch {
                managementError = UserFacingError.message(for: error, context: .write)
                    ?? "Something went wrong. Please try again."
            }
        }
    }

    private func syncNotificationRegistration() async {
        if let uid = appState.currentUserId {
            await appState.notificationService.saveToken(for: uid)
        } else {
            await appState.notificationService.syncWithSystem()
        }
    }
}

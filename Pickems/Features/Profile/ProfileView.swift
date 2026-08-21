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
    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var showDeleteAccountSheet = false
    @State private var showTeamPicker = false
    @State private var managementError: String?
    @State private var presentedHelp: HelpTopic?
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
                howToPlaySection
                legalSection
                accountActionsSection
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .pickemsRefreshable(isRefreshing: $isRefreshing) {
                await appState.authService.refreshSession()
                await appState.refreshLeagueData()
                await appState.notificationService.refreshAuthorizationStatus()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showTeamPicker = true
                        } label: {
                            teamThemeToolbarLabel
                        }
                        .accessibilityLabel("Team Theme")
                        .accessibilityHint("Opens favorite team picker to theme the app")

                        HelpInfoButton(
                            topic: PickemsHelp.profileOverview,
                            alignment: .center,
                            presentedTopic: $presentedHelp,
                            isToolbar: true
                        )
                    }
                }
                .sharedBackgroundVisibility(.hidden)
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
            .sheet(isPresented: $showDeleteAccountSheet) {
                DeleteAccountConfirmSheet()
                    .pickemsEnvironment(appState)
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
                Button("Continue", role: .destructive) { showDeleteAccountSheet = true }
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Deadline reminders")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(notificationExplanation)
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(PickemsColors.cardBackground)

            Toggle(isOn: selectionDeadlineToggle) {
                Label("Selection deadlines", systemImage: "american.football.fill")
            }
            .listRowBackground(PickemsColors.cardBackground)

            Toggle(isOn: pickemsDeadlineToggle) {
                Label("Pickems deadlines", systemImage: "checkmark.circle")
            }
            .listRowBackground(PickemsColors.cardBackground)

            notificationActionControls
                .listRowBackground(PickemsColors.cardBackground)
        } header: {
            HStack {
                Text("Notifications")
                Spacer()
                HelpInfoButton(
                    topic: PickemsHelp.notifications,
                    size: .callout,
                    presentedTopic: $presentedHelp
                )
            }
        } footer: {
            Text(notificationFooter)
        }
    }

    private var selectionDeadlineToggle: Binding<Bool> {
        Binding(
            get: { appState.authService.currentUser?.wantsSelectionDeadlineAlerts ?? true },
            set: { enabled in Task { await setDeadlinePref(selection: enabled, pickems: nil) } }
        )
    }

    private var pickemsDeadlineToggle: Binding<Bool> {
        Binding(
            get: { appState.authService.currentUser?.wantsPickemsDeadlineAlerts ?? true },
            set: { enabled in Task { await setDeadlinePref(selection: nil, pickems: enabled) } }
        )
    }

    private func setDeadlinePref(selection: Bool?, pickems: Bool?) async {
        let nextSelection = selection ?? (appState.authService.currentUser?.wantsSelectionDeadlineAlerts ?? true)
        let nextPickems = pickems ?? (appState.authService.currentUser?.wantsPickemsDeadlineAlerts ?? true)
        if selection == true || pickems == true {
            await appState.notificationService.refreshAuthorizationStatus()
            switch appState.notificationService.authorizationStatus {
            case .notDetermined:
                await appState.notificationService.requestPermission()
            case .denied:
                appState.notificationService.openSystemSettings()
            default:
                break
            }
        }
        do {
            try await appState.authService.updateNotificationPrefs(
                selectionDeadlines: nextSelection,
                pickemsDeadlines: nextPickems
            )
        } catch {
            managementError = UserFacingError.message(for: error, context: .write)
                ?? error.localizedDescription
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
        "Get a nudge before Selection and Pickems deadlines. Game-final and scored-week alerts still follow iOS permission."
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
            if let group = appState.groupService.selectedGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text("Invite code \(group.inviteCode)")
                        .font(.caption.monospaced())
                        .foregroundStyle(PickemsColors.textSecondary)
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

                InviteShareButton(group: group)
                    .listRowBackground(PickemsColors.cardBackground)
            }

            Button {
                showJoinSheet = true
            } label: {
                Label("Join a League", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderless)
            .listRowBackground(PickemsColors.cardBackground)

            Button {
                showCreateWizard = true
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
                    size: .callout,
                    presentedTopic: $presentedHelp
                )
            }
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
                PickemsHaptics.success()
            } catch {
                managementError = UserFacingError.message(for: error, context: .write) ?? "Something went wrong. Please try again."
            }
        }
    }

    private func signOut() {
        do {
            try appState.authService.signOut()
            appState.groupService.resetSession()
        } catch {
            managementError = UserFacingError.message(for: error, context: .write) ?? "Something went wrong. Please try again."
        }
    }
}

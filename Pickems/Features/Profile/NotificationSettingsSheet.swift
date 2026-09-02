import SwiftUI
import UserNotifications

/// Chooses which FCM alerts the signed-in user receives. Presented from Profile
/// so the tab stays a single row instead of a stack of toggles.
///
/// `All leagues` writes account defaults on `users/{uid}`. A specific league
/// writes overrides on that membership doc. Commissioner alerts only appear
/// for leagues the user actually commissions (or as defaults if they commission any).
struct NotificationSettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    /// `nil` = account defaults for every league.
    @State private var scopeGroupId: String?
    @State private var leagueMember: GroupMember?
    @State private var isLoadingLeague = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    systemPermissionControls
                        .listRowBackground(PickemsColors.cardBackground)
                } header: {
                    Text("iOS permission")
                } footer: {
                    Text(systemPermissionFooter)
                }

                if !appState.groupService.groups.isEmpty {
                    Section {
                        Picker("League", selection: $scopeGroupId) {
                            Text("All leagues (defaults)").tag(String?.none)
                            ForEach(appState.groupService.groups) { group in
                                Text(group.name).tag(Optional(group.id))
                            }
                        }
                        .listRowBackground(PickemsColors.cardBackground)
                        .accessibilityHint("Choose account defaults or a single league override")
                    } header: {
                        Text("Applies to")
                    } footer: {
                        Text(scopeFooter)
                    }
                }

                if isLoadingLeague {
                    Section {
                        ProgressView("Loading league settings…")
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                } else {
                    ForEach(visibleGroups) { group in
                        Section {
                            ForEach(NotificationPrefCategory.categories(in: group)) { category in
                                prefToggle(category)
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
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
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if scopeGroupId == nil {
                    scopeGroupId = appState.groupService.selectedGroup?.id
                }
                await appState.notificationService.syncWithSystem()
                if let uid = appState.currentUserId {
                    await appState.notificationService.saveToken(for: uid)
                }
                await loadLeagueMember()
            }
            .onChange(of: scopeGroupId) { _, _ in
                Task { await loadLeagueMember() }
            }
        }
    }

    private var visibleGroups: [NotificationPrefCategory.Group] {
        NotificationPrefCategory.Group.allCases.filter { group in
            if group == .commissioner { return showsCommissionerSection }
            return true
        }
    }

    private var showsCommissionerSection: Bool {
        guard let userId = appState.currentUserId else { return false }
        if let groupId = scopeGroupId {
            return appState.groupService.groups.first(where: { $0.id == groupId })?.commissionerId == userId
        }
        return appState.groupService.groups.contains { $0.commissionerId == userId }
    }

    private var scopedGroup: PickemGroup? {
        guard let scopeGroupId else { return nil }
        return appState.groupService.groups.first { $0.id == scopeGroupId }
    }

    private var scopeFooter: String {
        if let group = scopedGroup {
            if showsCommissionerSection {
                return "These switches apply only to \(group.name). Commissioner alerts are included because you run this league."
            }
            return "These switches apply only to \(group.name). Account defaults still apply to your other leagues."
        }
        return "Defaults for every league. Open a league here to override one without changing the others."
    }

    @ViewBuilder
    private func prefToggle(_ category: NotificationPrefCategory) -> some View {
        Toggle(isOn: binding(for: category)) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text(category.subtitle)
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: category.systemImage)
                    .foregroundStyle(theme.accent)
            }
        }
        .listRowBackground(PickemsColors.cardBackground)
        .accessibilityHint(category.subtitle)
    }

    @ViewBuilder
    private var systemPermissionControls: some View {
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
                Task {
                    await appState.notificationService.requestPermission()
                    if let uid = appState.currentUserId {
                        await appState.notificationService.saveToken(for: uid)
                    }
                }
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

    private var systemPermissionFooter: String {
        switch appState.notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "To block every Pickems alert, use Open Settings → Notifications."
        case .denied:
            return "iOS blocked alerts for Pickems. Enable them in Settings, then choose types here."
        default:
            return "You’ll get an iOS permission prompt when you tap Allow notifications."
        }
    }

    private func isEnabled(_ category: NotificationPrefCategory) -> Bool {
        let defaults = appState.authService.currentUser
        if let leagueMember, scopeGroupId != nil {
            return leagueMember.wants(category, defaults: defaults)
        }
        return defaults?.wants(category) ?? true
    }

    private func binding(for category: NotificationPrefCategory) -> Binding<Bool> {
        Binding(
            get: { isEnabled(category) },
            set: { enabled in
                Task { await setPref(category, enabled: enabled) }
            }
        )
    }

    private func loadLeagueMember() async {
        errorMessage = nil
        guard let groupId = scopeGroupId, let userId = appState.currentUserId else {
            leagueMember = nil
            isLoadingLeague = false
            return
        }
        isLoadingLeague = true
        leagueMember = await appState.groupService.fetchMember(groupId: groupId, userId: userId)
        isLoadingLeague = false
        if leagueMember == nil {
            errorMessage = "Couldn’t load settings for this league."
        }
    }

    private func setPref(_ category: NotificationPrefCategory, enabled: Bool) async {
        errorMessage = nil
        if enabled {
            await appState.notificationService.refreshAuthorizationStatus()
            switch appState.notificationService.authorizationStatus {
            case .notDetermined:
                await appState.notificationService.requestPermission()
            case .denied:
                appState.notificationService.openSystemSettings()
            default:
                if let uid = appState.currentUserId {
                    await appState.notificationService.saveToken(for: uid)
                }
            }
        }
        do {
            if let groupId = scopeGroupId, let userId = appState.currentUserId {
                if var member = leagueMember {
                    member.set(category, enabled: enabled)
                    leagueMember = member
                }
                try await appState.groupService.updateNotificationPref(
                    groupId: groupId,
                    userId: userId,
                    category: category,
                    enabled: enabled
                )
                if category == .chatMessages,
                   groupId == appState.groupService.selectedGroup?.id {
                    appState.chatService.isMuted = !enabled
                }
            } else {
                try await appState.authService.updateNotificationPref(category, enabled: enabled)
            }
        } catch {
            if let groupId = scopeGroupId, let userId = appState.currentUserId {
                leagueMember = await appState.groupService.fetchMember(groupId: groupId, userId: userId)
            }
            errorMessage = UserFacingError.message(for: error, context: .write)
                ?? error.localizedDescription
        }
    }
}

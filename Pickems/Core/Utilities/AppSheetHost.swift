import SwiftUI

/// Single `.sheet(item:)` for tab/root CTAs. Lives outside `RootView` so a
/// destination flicker (loading ↔ main) cannot tear the presenter down.
struct AppSheetHostModifier: ViewModifier {
    var appState: AppState
    /// Last non-nil league, so a momentary `selectedGroup == nil` does not
    /// tear Commissioner Settings (and every sheet stacked on it) down.
    @State private var retainedSettingsGroup: PickemGroup?

    func body(content: Content) -> some View {
        @Bindable var appState = appState
        content
            .onChange(of: appState.groupService.selectedGroup?.id, initial: true) { (_: String?, _: String?) in
                rememberSettingsGroup(settingsOpen: appState.presentedSheet == .commissionerSettings)
            }
            .onChange(of: appState.presentedSheet) { (_: AppSheet?, _: AppSheet?) in
                rememberSettingsGroup(settingsOpen: appState.presentedSheet == .commissionerSettings)
            }
            .sheet(
                item: presentedSheetBinding,
                onDismiss: {
                    appState.picksViewModel.selectionBrowseIntent = .own
                    // Sheet is gone. Follow the live league again, or drop the pin
                    // when nothing is selected so the next open cannot revive a
                    // league the member already left.
                    rememberSettingsGroup(settingsOpen: false)
                }
            ) { (sheet: AppSheet) in
                appSheetContent(sheet)
                    .pickemsEnvironment(appState)
            }
            .presentsHelp()
    }

    private var presentedSheetBinding: Binding<AppSheet?> {
        Binding(
            get: {
                appState.liveConfig.requiresUpdate ? nil : appState.presentedSheet
            },
            set: { (sheet: AppSheet?) in appState.presentedSheet = sheet }
        )
    }

    /// While Settings are open, a pin for another league stays put. A nil
    /// flicker does not clear it. Once Settings are closed, the pin follows
    /// the live selection (including clearing it).
    private func rememberSettingsGroup(settingsOpen: Bool) {
        guard let live = appState.groupService.selectedGroup else {
            if !settingsOpen {
                retainedSettingsGroup = nil
            }
            return
        }
        if !settingsOpen || retainedSettingsGroup == nil || retainedSettingsGroup?.id == live.id {
            retainedSettingsGroup = live
        }
    }

    @ViewBuilder
    private func appSheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .gameBrowse:
            GameBrowseView(seedGames: appState.picksViewModel.espnGames) { games in
                try await appState.picksViewModel.saveBrowseSelections(games, appState: appState)
            }
        case .joinGroup:
            JoinGroupSheet(initialCode: appState.pendingInviteCode ?? "")
        case .createLeague:
            CreateGroupWizardView()
        case .favoriteTeam(let isOnboardingPrompt):
            FavoriteTeamPickerView(isOnboardingPrompt: isOnboardingPrompt)
        case .commissionerSettings:
            commissionerSettingsSheet
        case .submissionStatus:
            SubmissionStatusView()
        case .editProfile:
            EditProfileSheet()
        case .notificationSettings:
            NotificationSettingsSheet()
        case .deleteAccount:
            DeleteAccountConfirmSheet()
        case .stayOnTime:
            StayOnTimeSheet()
        case .coverMoment(let gameLabel, let resultTitle, let recordText, let rankText):
            CoverMomentView(
                gameLabel: gameLabel,
                resultTitle: resultTitle,
                recordText: recordText,
                rankText: rankText,
                shareSource: appState.weeklyShareSource()
            )
        case .gameDetail(let gameId):
            GameDetailSheet(gameId: gameId)
        }
    }

    /// Identity is the league id, not the `PickemGroup` value. A listener
    /// snapshot used to rebuild Settings and dismiss every sheet on it.
    private var settingsGroupId: String? {
        CommissionerSheetStability.presenterGroupId(
            liveGroupId: appState.groupService.selectedGroup?.id,
            retainedGroupId: retainedSettingsGroup?.id
        )
    }

    @ViewBuilder
    private var commissionerSettingsSheet: some View {
        if let groupId = settingsGroupId {
            CommissionerSettingsView(groupId: groupId, seed: seedGroup(for: groupId))
        } else {
            missingSettingsLeague
        }
    }

    private func seedGroup(for groupId: String) -> PickemGroup {
        if let retained = retainedSettingsGroup, retained.id == groupId { return retained }
        if let live = appState.groupService.selectedGroup, live.id == groupId { return live }
        if let listed = appState.groupService.groups.first(where: { $0.id == groupId }) { return listed }
        return CommissionerSheetStability.placeholderGroup(id: groupId)
    }

    private var missingSettingsLeague: some View {
        NavigationStack {
            ContentUnavailableView(
                "No League Selected",
                systemImage: "person.3",
                description: Text("Select a league, then open Commissioner Settings again.")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { appState.dismissSheet() }
                }
            }
        }
    }
}

extension View {
    func appSheetHost(_ appState: AppState) -> some View {
        modifier(AppSheetHostModifier(appState: appState))
    }
}

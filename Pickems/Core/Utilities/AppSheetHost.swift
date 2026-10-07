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
                rememberSettingsGroup()
            }
            .sheet(
                item: presentedSheetBinding,
                onDismiss: {
                    appState.picksViewModel.selectionBrowseIntent = .own
                    if appState.groupService.selectedGroup == nil {
                        retainedSettingsGroup = nil
                    }
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

    private func rememberSettingsGroup() {
        if let group = appState.groupService.selectedGroup {
            retainedSettingsGroup = group
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
        }
    }

    /// Prefer the live league. Fall back to the last one so a nil flicker
    /// keeps the same `CommissionerSettingsView` identity.
    private var settingsGroup: PickemGroup? {
        appState.groupService.selectedGroup ?? retainedSettingsGroup
    }

    @ViewBuilder
    private var commissionerSettingsSheet: some View {
        if let group = settingsGroup {
            CommissionerSettingsView(group: group)
        } else {
            missingSettingsLeague
        }
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

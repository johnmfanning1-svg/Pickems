import SwiftUI

/// Single `.sheet(item:)` for tab/root CTAs. Lives outside `RootView` so a
/// destination flicker (loading ↔ main) cannot tear the presenter down.
struct AppSheetHostModifier: ViewModifier {
    var appState: AppState

    func body(content: Content) -> some View {
        @Bindable var appState = appState
        content
            .sheet(
                item: Binding(
                    get: {
                        appState.liveConfig.requiresUpdate ? nil : appState.presentedSheet
                    },
                    set: { appState.presentedSheet = $0 }
                ),
                onDismiss: {
                    appState.picksViewModel.selectionBrowseIntent = .own
                }
            ) { sheet in
                appSheetContent(sheet)
                    .pickemsEnvironment(appState)
            }
            .presentsHelp()
    }

    @ViewBuilder
    private func appSheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .gameBrowse:
            GameBrowseView { game in
                appState.picksViewModel.handleGameSelection(game, appState: appState)
            }
        case .joinGroup:
            JoinGroupSheet(initialCode: appState.pendingInviteCode ?? "")
        case .createLeague:
            CreateGroupWizardView()
        case .favoriteTeam(let isOnboardingPrompt):
            FavoriteTeamPickerView(isOnboardingPrompt: isOnboardingPrompt)
        case .commissionerSettings:
            Group {
                if let group = appState.groupService.selectedGroup {
                    CommissionerSettingsView(group: group)
                } else {
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
        case .submissionStatus:
            SubmissionStatusView()
        case .editProfile:
            EditProfileSheet()
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
}

extension View {
    func appSheetHost(_ appState: AppState) -> some View {
        modifier(AppSheetHostModifier(appState: appState))
    }
}

import SwiftUI

/// Weekly commissioner tools. These used to live on Selections / Pickems / Leagues.
struct CommissionerWeekAdminSections: View {
    @Environment(AppState.self) private var appState

    @Binding var showSelectionDeadlineSheet: Bool
    @Binding var showPickDeadlineSheet: Bool
    @Binding var showAdminGameBrowse: Bool
    @State private var showReopenSelectionsConfirm = false
    @State private var showSubmissionStatus = false

    private var picksVM: PicksViewModel { appState.picksViewModel }
    private var week: WeekSummary? { appState.groupService.currentWeek }
    private var uniqueGames: Int {
        Set(
            appState.pickService.nominations.map(\.espnEventId)
                + appState.pickService.slateGames.map(\.espnEventId)
        ).count
    }

    var body: some View {
        weekStatusSection
        selectionsAdminSection
        slateSection
        pickemsAdminSection
        tiesSection
            .task {
                await picksVM.ensureTeamRanks(appState: appState)
            }
            .sheet(isPresented: $showSubmissionStatus) {
                SubmissionStatusView()
                    .pickemsEnvironment(appState)
            }
    }

    @ViewBuilder
    private var weekStatusSection: some View {
        Section {
            if let week {
                LabeledContent("Week", value: week.displayLabel)
                    .listRowBackground(PickemsColors.cardBackground)
                LabeledContent("Status", value: week.status.rawValue.capitalized)
                    .listRowBackground(PickemsColors.cardBackground)

                if week.status == .selection, !week.skipsSelection {
                    if week.selectionDeadline == nil {
                        Button("Set Selection Deadline") { showSelectionDeadlineSheet = true }
                            .listRowBackground(PickemsColors.cardBackground)
                    } else {
                        Button("Edit Selection Deadline") { showSelectionDeadlineSheet = true }
                            .listRowBackground(PickemsColors.cardBackground)
                    }

                    let target = appState.groupService.selectedGroup?.rules.expectedSlateSize(
                        memberCount: max(appState.groupService.selectedGroup?.memberCount ?? 1, 1)
                    ) ?? max(week.slateSize, 1)
                    if week.isSelectionDeadlinePassed {
                        if uniqueGames < target {
                            Button("Fill Remaining Games") {
                                showAdminGameBrowse = true
                            }
                            .listRowBackground(PickemsColors.cardBackground)
                        }
                        Button("Open With \(uniqueGames) Game\(uniqueGames == 1 ? "" : "s")") {
                            picksVM.openWeekWithCurrentSlate(appState: appState)
                        }
                        .disabled(uniqueGames == 0)
                        .listRowBackground(PickemsColors.cardBackground)
                    } else {
                        Button("Open Week Early") {
                            picksVM.lockSlateEarly(appState: appState)
                        }
                        .disabled(uniqueGames == 0)
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                } else if WeekTransition.canReopenSelections(week) {
                    Button("Reopen Selections") {
                        showReopenSelectionsConfirm = true
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                }
            } else {
                Text("No active week.")
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("This Week")
        } footer: {
            Text("Deadlines, lock-early, opening the slate, and reopening Selections live here — not on the Selections tab.")
        }
        .alert("Reopen Selections?", isPresented: $showReopenSelectionsConfirm) {
            Button("Reopen Selections") {
                picksVM.reopenSelections(appState: appState)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Members can add and remove Selections again. Pickems close until you open the week.")
        }
    }

    @ViewBuilder
    private var selectionsAdminSection: some View {
        if let week, WeekTransition.commissionerCanManageSelections(week),
           week.selectionMode == .member,
           let groupId = appState.groupService.selectedGroup?.id {
            Section {
                ForEach(appState.groupService.members) { member in
                    NavigationLink {
                        CommissionerManageSelectionsSheet(
                            member: member,
                            week: week,
                            groupId: groupId
                        )
                    } label: {
                        Label("Manage Selections — \(member.displayName)", systemImage: "american.football")
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                }
            } header: {
                Text("Selections Admin")
            } footer: {
                Text("Remove, replace, or add a member's Selections. You can also do this from the Selections tab.")
            }
        }
    }

    @ViewBuilder
    private var slateSection: some View {
        let games = appState.pickService.displaySlateGames
        if !games.isEmpty, let week, WeekTransition.isSlateEditable(week) || week.status == .selection {
            Section {
                ForEach(games) { game in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            TeamDisplay.matchupLabel(
                                awayAbbreviation: game.awayTeamName,
                                awayRank: appState.picksViewModel.teamRanks.rank(for: game.awayTeamId),
                                homeAbbreviation: game.homeTeamName,
                                homeRank: appState.picksViewModel.teamRanks.rank(for: game.homeTeamId),
                                separator: game.matchupSeparator
                            )
                        )
                            .foregroundStyle(PickemsColors.textPrimary)
                        HStack {
                            Button("Edit Spread") { picksVM.spreadEditGame = game }
                            if !week.skipsSelection {
                                Spacer()
                                Button("Remove Selection", role: .destructive) {
                                    removeSlateItem(game, week: week)
                                }
                            }
                        }
                        .font(.caption)
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                }
            } header: {
                Text("This Week's Slate")
            } footer: {
                Text("Edit lines or remove a Selection. Members remake their own Selections on the Selections tab before the deadline.")
            }
        }
    }

    private func removeSlateItem(_ game: SlateGame, week: WeekSummary) {
        if let live = appState.pickService.slateGames.first(where: {
            $0.id == game.id || $0.espnEventId == game.espnEventId
        }) {
            picksVM.removeCommissionerGame(live, week: week, appState: appState)
        } else if let nom = appState.pickService.nominations.first(where: { $0.espnEventId == game.espnEventId }) {
            let rules = appState.groupService.selectedGroup?.rules ?? .default
            picksVM.removeNomination(nom, rules: rules, appState: appState)
        }
    }

    @ViewBuilder
    private var pickemsAdminSection: some View {
        if let week, WeekTransition.arePickemsOpen(week) {
            Section {
                Button {
                    showSubmissionStatus = true
                } label: {
                    Label("See who's in", systemImage: "person.crop.circle.badge.clock")
                }
                .listRowBackground(PickemsColors.cardBackground)

                Button(week.status == .locked ? "Reopen Pickems" : (
                    PickDeadlineCalculator.isPast(week.pickDeadline) ? "Extend / Unlock Deadline" : "Set Pickems Deadline"
                )) {
                    showPickDeadlineSheet = true
                }
                .listRowBackground(PickemsColors.cardBackground)

                if let groupId = appState.groupService.selectedGroup?.id {
                    ForEach(appState.groupService.members) { member in
                        NavigationLink {
                            CommissionerManagePicksSheet(
                                member: member,
                                week: week,
                                groupId: groupId,
                                slateGames: appState.pickService.slateGames
                            )
                        } label: {
                            Label("Manage Pickems — \(member.displayName)", systemImage: "slider.horizontal.3")
                        }
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                }
            } header: {
                Text("Pickems Admin")
            } footer: {
                Text("See who's in is also on the Pickems tab for every member. Force or clear a member's Pickems, or change the deadline, here. This never removes Selections.")
            }
        }
    }

    @ViewBuilder
    private var tiesSection: some View {
        if appState.groupService.selectedGroup?.rules.tieBreaker == .commissionerOverride {
            let tied = appState.rankedStandings(weekly: true).filter { $0.isTied && $0.weeklyWins > 0 }
            if !tied.isEmpty {
                Section {
                    ForEach(tied) { entry in
                        Button("Resolve tie — \(entry.displayName)") {
                            Task {
                                guard let groupId = appState.groupService.selectedGroup?.id else { return }
                                try? await appState.groupService.resolveTie(
                                    groupId: groupId,
                                    standingUserId: entry.id
                                )
                            }
                        }
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                } header: {
                    Text("Resolve Ties")
                }
            }
        }
    }
}

import SwiftUI

/// Weekly commissioner tools. These used to live on Selections / Pickems / Leagues.
struct CommissionerWeekAdminSections: View {
    @Environment(AppState.self) private var appState

    @Binding var showSelectionDeadlineSheet: Bool
    @Binding var showPickDeadlineSheet: Bool
    @Binding var showAdminGameBrowse: Bool

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
        slateSection
        pickemsAdminSection
        tiesSection
    }

    @ViewBuilder
    private var weekStatusSection: some View {
        Section {
            if let week {
                LabeledContent("Week", value: week.displayLabel)
                    .listRowBackground(PickemsColors.cardBackground)
                LabeledContent("Status", value: week.status.rawValue.capitalized)
                    .listRowBackground(PickemsColors.cardBackground)

                if week.status == .selection {
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
                                Task {
                                    await picksVM.browseGames(appState: appState, present: false)
                                    showAdminGameBrowse = !picksVM.espnGames.isEmpty
                                }
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
                }
            } else {
                Text("No active week.")
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("This Week")
        } footer: {
            Text("Deadlines, lock-early, and opening the slate live here — not on the Selections tab.")
        }
    }

    @ViewBuilder
    private var slateSection: some View {
        let games = appState.pickService.slateGames
        if !games.isEmpty, let week, WeekTransition.isSlateEditable(week) {
            Section {
                ForEach(games) { game in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(game.awayTeamName) @ \(game.homeTeamName)")
                            .foregroundStyle(PickemsColors.textPrimary)
                        HStack {
                            Button("Edit Spread") { picksVM.spreadEditGame = game }
                            Spacer()
                            Button("Remove Selection", role: .destructive) {
                                picksVM.removeCommissionerGame(game, week: week, appState: appState)
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

    @ViewBuilder
    private var pickemsAdminSection: some View {
        if let week, WeekTransition.arePickemsOpen(week) {
            Section {
                NavigationLink {
                    SubmissionStatusView(
                        members: appState.groupService.members,
                        submissions: appState.pickService.submissions,
                        slateSize: appState.pickService.slateGames.count
                    )
                } label: {
                    Label("Submission chase", systemImage: "person.crop.circle.badge.clock")
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
                Text("Force or clear a member's Pickems, or change the Pickems deadline. This never removes Selections.")
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

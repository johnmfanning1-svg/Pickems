import SwiftUI

struct PicksView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = PicksViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let week = appState.groupService.currentWeek {
                        SeasonWeekHeader(label: week.displayLabel)
                        statusContent(for: week)
                    } else {
                        EmptyStateView(
                            icon: "sportscourt.fill",
                            title: "No Active Week",
                            message: "Join a group to start making picks.",
                            help: PickemsHelp.picksOverview
                        )
                    }

                    if let error = appState.pickService.errorMessage {
                        ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                    }
                }
                .padding(.vertical)
            }
            .pickemsScreenBackground()
            .navigationTitle("Picks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HelpToolbarButton(topic: PickemsHelp.picksOverview)
                }
            }
            .refreshable { await viewModel.loadWeek(appState: appState) }
            .sheet(isPresented: $viewModel.showGameBrowse) {
                GameBrowseView(games: viewModel.espnGames) { game in
                    viewModel.handleGameSelection(game, appState: appState)
                }
            }
            .sheet(item: $viewModel.spreadEditGame) { game in
                SpreadEditorSheet(game: game) { spread, spreadTeamId in
                    viewModel.updateSpread(game, spread: spread, spreadTeamId: spreadTeamId, appState: appState)
                }
            }
            .confirmationDialog("Submit your picks?", isPresented: $viewModel.showConfirmSubmit, titleVisibility: .visible) {
                Button("Submit Picks") {
                    if let week = appState.groupService.currentWeek {
                        viewModel.submitPicks(week: week, appState: appState)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won't be able to change picks after submitting.")
            }
            .task(id: appState.groupService.selectedGroup?.id) {
                await viewModel.loadWeek(appState: appState)
            }
            .onChange(of: appState.pickService.userPick?.picks) { _, newPicks in
                viewModel.syncDraftFromServer(newPicks)
            }
        }
    }

    @ViewBuilder
    private func statusContent(for week: WeekSummary) -> some View {
        switch week.status {
        case .selection: selectionPhase(week: week)
        case .picking: pickingPhase(week: week)
        case .locked, .scored: lockedPhase(week: week)
        }
    }

    @ViewBuilder
    private func selectionPhase(week: WeekSummary) -> some View {
        let rules = appState.groupService.selectedGroup?.rules ?? .default
        if rules.selectionMode == .commissioner && appState.isCommissioner {
            commissionerSelectionUI(week: week, rules: rules)
        } else if rules.selectionMode == .member {
            memberNominationUI(week: week, rules: rules)
        } else {
            EmptyStateView(
                icon: "hourglass",
                title: "Waiting for Commissioner",
                message: "Your commissioner is building this week's slate.",
                help: PickemsHelp.commissionerSlate
            )
        }
    }

    private func commissionerSelectionUI(week: WeekSummary, rules: GroupRules) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Build Slate",
                subtitle: "\(appState.pickService.slateGames.count) of \(rules.slateSize) games selected",
                help: PickemsHelp.commissionerSlate
            )

            PrimaryButton(title: "Add Game", isLoading: viewModel.isLoadingGames) {
                Task {
                    await viewModel.loadESPNGames(appState: appState)
                    viewModel.showGameBrowse = true
                }
            }
            .padding(.horizontal)

            SecondaryButton("Bulk Import Scheduled", icon: "square.stack.3d.up.fill") {
                Task { await viewModel.bulkImportScheduled(week: week, rules: rules, appState: appState) }
            }
            .padding(.horizontal)

            ForEach(appState.pickService.slateGames) { game in
                VStack(spacing: 4) {
                    GamePickRow(game: game, selectedTeamId: nil, onSelect: { _ in })
                    HStack {
                        Button("Edit Spread") { viewModel.spreadEditGame = game }
                            .font(.caption).foregroundStyle(PickemsColors.accent)
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.removeCommissionerGame(game, week: week, appState: appState)
                        } label: {
                            Label("Remove", systemImage: "trash").font(.caption)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.horizontal)
            }
        }
    }

    private func memberNominationUI(week: WeekSummary, rules: GroupRules) -> some View {
        let userId = appState.currentUserId ?? ""
        let userNoms = appState.pickService.nominations.filter { $0.submittedBy == userId }.count

        return VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Nominate Games",
                subtitle: "You: \(userNoms)/\(rules.selectionsPerMember) · Group: \(appState.pickService.nominations.count)/\(rules.slateSize)",
                help: PickemsHelp.nominations
            )

            if appState.isCommissioner {
                SecondaryButton("Lock Slate Early", icon: "lock.fill") {
                    viewModel.lockSlateEarly(appState: appState)
                }
                .padding(.horizontal)
            }

            PrimaryButton(title: "Nominate Game", isLoading: viewModel.isLoadingGames) {
                Task {
                    await viewModel.loadESPNGames(appState: appState)
                    viewModel.showGameBrowse = true
                }
            }
            .padding(.horizontal)

            ForEach(appState.pickService.nominations) { nom in
                PickemsCard {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(nom.awayTeamName) @ \(nom.homeTeamName)")
                            Text("by \(nom.submitterName)").font(.caption).foregroundStyle(PickemsColors.textSecondary)
                        }
                        Spacer()
                        if appState.isCommissioner || nom.submittedBy == userId {
                            Button(role: .destructive) {
                                viewModel.removeNomination(nom, rules: rules, appState: appState)
                            } label: {
                                Image(systemName: "trash").foregroundStyle(PickemsColors.accent)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func pickingPhase(week: WeekSummary) -> some View {
        let pastDeadline = ScoringEngine.isPastDeadline(deadline: week.pickDeadline)

        return VStack(spacing: 16) {
            PickemsSectionHeader(title: "Spread Picks", subtitle: "Tap a team to pick against the spread", help: PickemsHelp.spreadPicks)

            if let deadline = week.pickDeadline {
                PickDeadlineBanner(deadline: deadline, isPast: pastDeadline)
            }

            if appState.pickService.userPick?.isLocked == true {
                StatusBadge(text: "Submitted", color: PickemsColors.success).padding(.horizontal)
            }

            if appState.isCommissioner {
                SubmissionStatusView(
                    members: appState.groupService.members,
                    submissions: appState.pickService.submissions
                )
            }

            ForEach(appState.pickService.slateGames) { game in
                VStack(spacing: 4) {
                    GamePickRow(
                        game: game,
                        selectedTeamId: viewModel.draftPicks[game.id],
                        isDisabled: appState.pickService.userPick?.isLocked == true || pastDeadline
                    ) { teamId in
                        viewModel.draftPicks[game.id] = teamId
                        viewModel.saveDraft(appState: appState)
                    }
                    if appState.isCommissioner && !pastDeadline {
                        Button("Edit Spread") { viewModel.spreadEditGame = game }
                            .font(.caption).foregroundStyle(PickemsColors.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.horizontal)
            }

            if appState.pickService.userPick?.isLocked != true {
                PrimaryButton(title: pastDeadline ? "Deadline Passed" : "Submit Picks") {
                    viewModel.showConfirmSubmit = true
                }
                .disabled(pastDeadline || viewModel.draftPicks.count < appState.pickService.slateGames.count)
                .padding(.horizontal)
            }
        }
    }

    private func lockedPhase(week: WeekSummary) -> some View {
        VStack(spacing: 12) {
            StatusBadge(
                text: week.status == .scored ? "Scored" : "Locked",
                color: week.status == .scored ? PickemsColors.success : PickemsColors.textSecondary
            )
            .padding(.horizontal)

            ForEach(appState.pickService.slateGames) { game in
                GamePickRow(
                    game: game,
                    selectedTeamId: viewModel.draftPicks[game.id],
                    isDisabled: true,
                    liveCard: viewModel.livePickCards[game.espnEventId],
                    onSelect: { _ in }
                )
                .padding(.horizontal)
            }

            VStack(spacing: 8) {
                NavigationLink { SeasonPickHistoryView() } label: {
                    Label("Season History", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(PickemsColors.accent)
                }
                NavigationLink { PickHistoryView() } label: {
                    Label("This Week's Picks", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(PickemsColors.accent)
                }
                NavigationLink { GroupPicksView() } label: {
                    Label("View Group Picks", systemImage: "person.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(PickemsColors.accent)
                }
            }
            .padding(.horizontal)
        }
        .task(id: week.id) {
            if let group = appState.groupService.selectedGroup {
                await appState.pickService.loadAllPicks(groupId: group.id, weekId: week.id)
            }
            viewModel.startLiveRefresh(week: week, appState: appState)
        }
        .onDisappear { viewModel.stopLiveRefresh() }
    }
}

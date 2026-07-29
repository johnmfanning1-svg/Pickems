import SwiftUI

/// Composition layer for building the slate, making picks, or monitoring live results
/// from Groups. Reuses `PicksViewModel` — no new business logic.
struct GroupSlateView: View {
    let group: PickemGroup
    let week: WeekSummary

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var viewModel = PicksViewModel()

    private var activeWeek: WeekSummary {
        if let current = appState.groupService.currentWeek, current.id == week.id {
            return current
        }
        return week
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SeasonWeekHeader(label: activeWeek.displayLabel)
                phaseContent(for: activeWeek)

                if let error = appState.pickService.errorMessage {
                    ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                }
            }
            .padding(.vertical)
        }
        .pickemsScreenBackground()
        .navigationTitle(navigationTitle(for: activeWeek.status))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpToolbarButton(topic: helpTopic(for: activeWeek.status))
            }
        }
        .sheet(isPresented: $viewModel.showGameBrowse) {
            GameBrowseView(
                games: viewModel.espnGames,
                nominatedEventIds: Set(
                    appState.pickService.nominations.map(\.espnEventId)
                        + appState.pickService.slateGames.map(\.espnEventId)
                ),
                nominatorNamesByEventId: {
                    var names = Dictionary(
                        appState.pickService.nominations.map { ($0.espnEventId, $0.submitterName) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for game in appState.pickService.slateGames where names[game.espnEventId] == nil {
                        names[game.espnEventId] = "the slate"
                    }
                    return names
                }()
            ) { game in
                viewModel.handleGameSelection(game, appState: appState)
            }
            .pickemsEnvironment(appState)
        }
        .sheet(item: $viewModel.spreadEditGame) { game in
            SpreadEditorSheet(game: game) { spread, spreadTeamId in
                viewModel.updateSpread(game, spread: spread, spreadTeamId: spreadTeamId, appState: appState)
            }
            .pickemsEnvironment(appState)
        }
        .confirmationDialog("Submit your picks?", isPresented: $viewModel.showConfirmSubmit, titleVisibility: .visible) {
            Button("Submit Picks") {
                viewModel.submitPicks(week: activeWeek, appState: appState)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can still edit your picks until the first game kicks off.")
        }
        .confirmationDialog("Submit your nominations?", isPresented: $viewModel.showConfirmNominations, titleVisibility: .visible) {
            Button("Submit Nominations") {
                viewModel.submitNominations(appState: appState)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can still swap your games until the slate locks at the first kickoff.")
        }
        .task(id: "\(group.id)-\(activeWeek.id)") {
            await viewModel.loadWeek(appState: appState)
        }
        .onChange(of: appState.groupService.currentWeek?.id) { _, _ in
            viewModel.refreshNominationSubmissionState(appState: appState)
        }
        .onChange(of: appState.pickService.userPick?.picks) { _, newPicks in
            viewModel.syncDraftFromServer(newPicks, confidenceGameId: appState.pickService.userPick?.confidenceGameId)
        }
    }

    // MARK: - Phase routing

    @ViewBuilder
    private func phaseContent(for week: WeekSummary) -> some View {
        switch week.status {
        case .selection:
            selectionPhase(week: week)
        case .picking:
            pickingPhase(week: week)
        case .locked, .scored:
            monitorPhase(week: week)
        }
    }

    // MARK: - Selection (build slate)

    @ViewBuilder
    private func selectionPhase(week: WeekSummary) -> some View {
        let rules = group.rules
        if rules.selectionMode == .commissioner && appState.isCommissioner {
            commissionerSelectionUI(week: week, rules: rules)
        } else if rules.selectionMode == .member {
            memberNominationUI(week: week, rules: rules)
        } else {
            ContentUnavailableView(
                "Waiting for Commissioner",
                systemImage: "hourglass",
                description: Text("Your commissioner is building this week's slate.")
            )
            .padding(.top, 24)
        }
    }

    private func commissionerSelectionUI(week: WeekSummary, rules: GroupRules) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Build Slate",
                subtitle: "\(appState.pickService.slateGames.count) of \(rules.slateSize) games selected",
                help: PickemsHelp.commissionerSlate
            )

            PrimaryButton(title: "Nominate Game", isLoading: viewModel.isLoadingGames) {
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

            if appState.pickService.slateGames.isEmpty {
                ContentUnavailableView(
                    "No Games Yet",
                    systemImage: "sportscourt",
                    description: Text("Add games to build this week's slate.")
                )
                .padding(.top, 16)
            } else {
                ForEach(appState.pickService.slateGames) { game in
                    VStack(spacing: 4) {
                        GamePickRow(game: game, selectedTeamId: nil, onSelect: { _ in })
                        HStack {
                            Button("Edit Spread") { viewModel.spreadEditGame = game }
                                .font(.caption).foregroundStyle(theme.accent)
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
    }

    private func memberNominationUI(week: WeekSummary, rules: GroupRules) -> some View {
        let userId = appState.currentUserId ?? ""
        let userNoms = appState.pickService.nominations.filter { $0.submittedBy == userId }.count
        let atLimit = userNoms >= rules.selectionsPerMember

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

            if atLimit {
                nominationSubmitSection(userNoms: userNoms, rules: rules)
            } else {
                PrimaryButton(title: "Nominate Game", isLoading: viewModel.isLoadingGames) {
                    Task {
                        await viewModel.loadESPNGames(appState: appState)
                        viewModel.showGameBrowse = true
                    }
                }
                .padding(.horizontal)
            }

            if appState.pickService.nominations.isEmpty {
                ContentUnavailableView(
                    "No Nominations Yet",
                    systemImage: "plus.rectangle.on.rectangle",
                    description: Text("Nominate a game to help build the slate.")
                )
                .padding(.top, 16)
            } else {
                ForEach(appState.pickService.nominations) { nom in
                    PickemsCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(nom.awayTeamName) @ \(nom.homeTeamName)")
                                Text(nominationSpreadLabel(nom))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.accent)
                                Text("by \(nom.submitterName)")
                                    .font(.caption)
                                    .foregroundStyle(PickemsColors.textSecondary)
                            }
                            Spacer()
                            if appState.isCommissioner || nom.submittedBy == userId {
                                Button(role: .destructive) {
                                    viewModel.removeNomination(nom, rules: rules, appState: appState)
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(theme.accent)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func nominationSpreadLabel(_ nom: Nomination) -> String {
        let abbr: String
        if nom.spreadTeamId == nom.homeTeamId {
            abbr = nom.homeTeamAbbreviation ?? String(nom.homeTeamName.prefix(4)).uppercased()
        } else if nom.spreadTeamId == nom.awayTeamId {
            abbr = nom.awayTeamAbbreviation ?? String(nom.awayTeamName.prefix(4)).uppercased()
        } else {
            abbr = nom.homeTeamAbbreviation
                ?? nom.awayTeamAbbreviation
                ?? String(nom.homeTeamName.prefix(4)).uppercased()
        }
        let magnitude = abs(nom.spread).formatted(.number.precision(.fractionLength(1)))
        return "\(abbr) -\(magnitude)"
    }

    @ViewBuilder
    private func nominationSubmitSection(userNoms: Int, rules: GroupRules) -> some View {
        if viewModel.didSubmitNominations {
            PickemsCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Nominations submitted", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(PickemsColors.success)
                    Text("Your \(userNoms) game\(userNoms == 1 ? "" : "s") \(userNoms == 1 ? "is" : "are") in. You can still edit them until the slate locks at the first kickoff.")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("You've picked your \(rules.selectionsPerMember) game\(rules.selectionsPerMember == 1 ? "" : "s"). Submit to lock in your nominations.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)

                PrimaryButton(title: "Submit Nominations") {
                    viewModel.showConfirmNominations = true
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Picking

    private func pickingPhase(week: WeekSummary) -> some View {
        let pastDeadline = ScoringEngine.isPastDeadline(deadline: week.pickDeadline)
        let slateGames = appState.pickService.slateGames

        return VStack(spacing: 16) {
            PickemsSectionHeader(
                title: "Spread Picks",
                subtitle: "Tap a team to pick against the spread",
                help: PickemsHelp.spreadPicks
            )

            if let deadline = week.pickDeadline {
                PickDeadlineBanner(deadline: deadline, isPast: pastDeadline)
            }

            if appState.pickService.userPick?.isLocked == true {
                VStack(alignment: .leading, spacing: 8) {
                    StatusBadge(text: "Submitted", color: PickemsColors.success)
                    if !pastDeadline {
                        Text("Changed your mind? You can still edit your picks until the first game kicks off.")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SecondaryButton("Edit Picks", icon: "pencil") {
                            viewModel.unlockPicksForEditing(appState: appState)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }

            if appState.isCommissioner {
                SubmissionStatusView(
                    members: appState.groupService.members,
                    submissions: appState.pickService.submissions
                )
            }

            if slateGames.isEmpty {
                ContentUnavailableView(
                    "Slate Not Ready",
                    systemImage: "sportscourt",
                    description: Text("Games will appear here once the slate is locked.")
                )
                .padding(.top, 16)
            } else {
                ForEach(slateGames) { game in
                    VStack(spacing: 4) {
                        GamePickRow(
                            game: game,
                            selectedTeamId: viewModel.draftPicks[game.id],
                            isDisabled: appState.pickService.userPick?.isLocked == true || pastDeadline,
                            showConfidenceToggle: group.rules.allowConfidencePick
                                && appState.pickService.userPick?.isLocked != true
                                && !pastDeadline,
                            isConfidence: viewModel.confidenceGameId == game.id,
                            onConfidenceToggle: {
                                viewModel.confidenceGameId = viewModel.confidenceGameId == game.id ? nil : game.id
                                viewModel.saveDraft(appState: appState)
                            }
                        ) { teamId in
                            viewModel.draftPicks[game.id] = teamId
                            viewModel.saveDraft(appState: appState)
                        }
                        if appState.isCommissioner && !pastDeadline {
                            Button("Edit Spread") { viewModel.spreadEditGame = game }
                                .font(.caption).foregroundStyle(theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if appState.pickService.userPick?.isLocked != true, !slateGames.isEmpty {
                PrimaryButton(title: pastDeadline ? "Deadline Passed" : "Submit Picks") {
                    viewModel.showConfirmSubmit = true
                }
                .disabled(pastDeadline || viewModel.draftPicks.count < slateGames.count)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Monitor (locked / scored)

    private func monitorPhase(week: WeekSummary) -> some View {
        let liveCards = Array(viewModel.livePickCards.values)
            .sorted { $0.kickoff < $1.kickoff }
        let picksByUserId = Dictionary(
            uniqueKeysWithValues: appState.pickService.allPicks.map { ($0.userId, $0) }
        )
        let members = appState.groupService.members.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        return VStack(spacing: 16) {
            StatusBadge(
                text: week.status == .scored ? "Scored" : "Locked",
                color: week.status == .scored ? PickemsColors.success : PickemsColors.textSecondary
            )
            .padding(.horizontal)

            if !liveCards.isEmpty {
                LiveScoreboardSection(
                    games: liveCards,
                    title: "Live Scoreboard",
                    subtitle: "Slate games this week",
                    help: PickemsHelp.liveScores
                )
            }

            if appState.pickService.slateGames.isEmpty {
                ContentUnavailableView(
                    "No Slate Games",
                    systemImage: "sportscourt",
                    description: Text("There are no games on this week's slate.")
                )
                .padding(.top, 16)
            } else {
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

                VStack(alignment: .leading, spacing: 12) {
                    PickemsSectionHeader(
                        title: "Group Results",
                        subtitle: "Picks with spreads",
                        help: PickemsHelp.spreadPicks
                    )

                    if members.isEmpty {
                        ContentUnavailableView(
                            "No Members",
                            systemImage: "person.3",
                            description: Text("League members will appear here.")
                        )
                    } else {
                        ForEach(members) { member in
                            memberResultsCard(
                                member: member,
                                pick: picksByUserId[member.id]
                            )
                        }
                    }
                }
            }
        }
        .task(id: week.id) {
            await appState.pickService.loadAllPicks(groupId: group.id, weekId: week.id)
            viewModel.startLiveRefresh(week: week, appState: appState)
        }
        .onDisappear { viewModel.stopLiveRefresh() }
    }

    private func memberResultsCard(member: GroupMember, pick: UserPick?) -> some View {
        PickemsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    InitialsAvatar(
                        initials: String(member.displayName.prefix(2)).uppercased(),
                        colorHex: member.avatarColorHex,
                        size: 28
                    )
                    Text(member.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PickemsColors.textPrimary)
                    Spacer()
                }

                if let pick, !pick.picks.isEmpty {
                    ForEach(appState.pickService.slateGames) { game in
                        PickResultRow(
                            game: game,
                            pickedTeamId: pick.picks[game.id],
                            showSpread: true
                        )
                    }
                } else {
                    Text("No picks submitted")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Titles / help

    private func navigationTitle(for status: WeekStatus) -> String {
        switch status {
        case .selection: return "Build Slate"
        case .picking: return "Make Picks"
        case .locked, .scored: return "Live Picks"
        }
    }

    private func helpTopic(for status: WeekStatus) -> HelpTopic {
        switch status {
        case .selection:
            return group.rules.selectionMode == .commissioner
                ? PickemsHelp.commissionerSlate
                : PickemsHelp.nominations
        case .picking:
            return PickemsHelp.spreadPicks
        case .locked, .scored:
            return PickemsHelp.liveScores
        }
    }
}

import SwiftUI

/// Composition layer for building the slate, making picks, or monitoring live results
/// from Groups. Reuses `PicksViewModel` — no new business logic.
struct GroupSlateView: View {
    let group: PickemGroup
    let week: WeekSummary

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var showSelectionDeadlineSheet = false
    @State private var showPickDeadlineSheet = false
    @State private var showIncompletePickemsAlert = false
    @State private var incompletePickemsAlertText = ""

    private var viewModel: PicksViewModel { appState.picksViewModel }

    private var activeWeek: WeekSummary {
        if let current = appState.groupService.currentWeek, current.id == week.id {
            return current
        }
        return week
    }

    var body: some View {
        @Bindable var viewModel = appState.picksViewModel
        ScrollView {
            VStack(spacing: 16) {
                SeasonWeekHeader(label: activeWeek.displayLabel)
                phaseContent(for: activeWeek)

                if let error = appState.pickService.errorMessage {
                    ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                }
                if let error = appState.groupService.errorMessage {
                    ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                }
            }
            .padding(.vertical)
        }
        .pickemsScreenBackground()
        .navigationTitle(navigationTitle(for: activeWeek.status))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            HelpToolbarItem(topic: helpTopic(for: activeWeek.status))
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
        .alert("Submit your Pickems?", isPresented: $viewModel.showConfirmSubmit) {
            Button("Submit Pickems") {
                viewModel.submitPicks(week: activeWeek, appState: appState)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can still edit your Pickems until lock.")
        }
        .alert("Submit your Selections?", isPresented: $viewModel.showConfirmNominations) {
            Button("Submit Selections") {
                viewModel.submitNominations(appState: appState)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SelectionPhaseCopy.confirmSubmit)
        }
            .alert("Finish your Pickems", isPresented: $showIncompletePickemsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(incompletePickemsAlertText)
            }
        .sheet(isPresented: $showSelectionDeadlineSheet) {
            SelectionDeadlineSheet(
                weekLabel: activeWeek.displayLabel,
                initialDeadline: activeWeek.selectionDeadline
            ) { deadline in
                viewModel.setSelectionDeadline(deadline, appState: appState)
            }
            .pickemsEnvironment(appState)
        }
        .sheet(isPresented: $showPickDeadlineSheet) {
            PickDeadlineEditorSheet(
                weekLabel: activeWeek.displayLabel,
                weekStatus: activeWeek.status,
                initialDeadline: activeWeek.pickDeadline,
                isPastDeadline: PickDeadlineCalculator.isPast(activeWeek.pickDeadline)
            ) { deadline, reopen, unlock in
                viewModel.setPickDeadline(
                    deadline,
                    reopenWeek: reopen,
                    unlockMemberPicks: unlock,
                    appState: appState
                )
            }
            .pickemsEnvironment(appState)
        }
        .task(id: "\(group.id)-\(activeWeek.id)") {
            await viewModel.loadWeek(appState: appState)
        }
        .onChange(of: appState.pendingSelectionDeadlinePrompt) { _, pending in
            if pending, appState.isCommissioner, activeWeek.status == .selection {
                showSelectionDeadlineSheet = true
                appState.pendingSelectionDeadlinePrompt = false
            }
        }
        .onChange(of: appState.groupService.currentWeek?.id) { _, _ in
            viewModel.refreshNominationSubmissionState(appState: appState)
        }
        .syncPicksDraftFromServer()
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
        let mode = week.selectionMode
        if mode == .commissioner && appState.isCommissioner {
            commissionerSelectionUI(week: week, rules: rules)
        } else if mode == .member {
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
        let memberCount = max(appState.groupService.selectedGroup?.memberCount ?? 1, 1)
        let target = rules.expectedSlateSize(memberCount: memberCount)
        return VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Build Slate",
                subtitle: "\(appState.pickService.slateGames.count) of \(target) games selected",
                help: PickemsHelp.commissionerSlate
            )

            PrimaryButton(title: "Add Game", isLoading: viewModel.isLoadingGames) {
                Task {
                    await viewModel.browseGames(appState: appState)
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
                                Label("Remove Selection", systemImage: "trash").font(.caption)
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
        let perMember = week.selectionsPerMember > 0 ? week.selectionsPerMember : rules.selectionsPerMember
        let userNoms = appState.pickService.nominations.filter { $0.submittedBy == userId }.count
        let atLimit = userNoms >= perMember
        let memberIds = group.memberIds
        var byUser: [String: Int] = [:]
        for nom in appState.pickService.nominations {
            byUser[nom.submittedBy, default: 0] += 1
        }
        let membersDone = memberIds.filter { (byUser[$0] ?? 0) >= perMember }.count
        let uniqueGames = Set(
            appState.pickService.nominations.map(\.espnEventId)
                + appState.pickService.slateGames.map(\.espnEventId)
        ).count
        let memberCount = max(memberIds.count, 1)
        let targetGames = rules.expectedSlateSize(memberCount: memberCount)
        let deadlinePassed = week.isSelectionDeadlinePassed
        let canMemberNominate = !deadlinePassed && !atLimit

        return VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Make Selections",
                subtitle: "You: \(userNoms)/\(perMember) · Members done: \(membersDone)/\(memberCount) · Games: \(uniqueGames)/\(targetGames)",
                help: PickemsHelp.nominations
            )

            if appState.isCommissioner {
                commissionerSelectionControls(week: week, uniqueGames: uniqueGames, deadlinePassed: deadlinePassed)
            } else if let deadline = week.selectionDeadline {
                ContextualTipBanner(
                    icon: "clock",
                    message: SelectionPhaseCopy.memberDeadlineBanner(
                        hasSelections: userNoms > 0,
                        deadline: deadline,
                        deadlinePassed: deadlinePassed
                    )
                )
                .padding(.horizontal)
            }

            if deadlinePassed, !appState.isCommissioner {
                // Members wait after deadline.
            } else if atLimit {
                nominationSubmitSection(userNoms: userNoms, perMember: perMember, week: week)
            } else if canMemberNominate {
                PrimaryButton(title: "Select Game", isLoading: viewModel.isLoadingGames) {
                    Task {
                        await viewModel.browseGames(appState: appState)
                    }
                }
                .padding(.horizontal)
            }

            if appState.pickService.nominations.isEmpty {
                ContentUnavailableView(
                    "No Selections Yet",
                    systemImage: "plus.rectangle.on.rectangle",
                    description: Text("Select a game to help build the slate.")
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
                            if !deadlinePassed, appState.isCommissioner || (nom.submittedBy == userId && !appState.pickService.didSubmitNominations) {
                                Button(role: .destructive) {
                                    viewModel.removeNomination(nom, rules: rules, appState: appState)
                                } label: {
                                    Label("Remove Selection", systemImage: "trash")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(theme.accent)
                                }
                                .accessibilityHint("Frees a slot so you can select a different game")
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func commissionerSelectionControls(
        week: WeekSummary,
        uniqueGames: Int,
        deadlinePassed: Bool
    ) -> some View {
        let target = appState.groupService.selectedGroup?.rules.expectedSlateSize(
            memberCount: max(appState.groupService.selectedGroup?.memberCount ?? 1, 1)
        ) ?? max(week.slateSize, 1)
        VStack(spacing: 8) {
            if week.selectionDeadline == nil {
                ContextualTipBanner(
                    icon: "bell.badge",
                    message: "Set a selection deadline so members finish early enough to make Pickems before kickoff."
                )
                PrimaryButton(title: "Set Selection Deadline") {
                    showSelectionDeadlineSheet = true
                }
            } else {
                SecondaryButton(
                    week.isSelectionDeadlinePassed
                        ? "Update Deadline"
                        : "Edit Selection Deadline",
                    icon: "calendar"
                ) {
                    showSelectionDeadlineSheet = true
                }
            }

            if deadlinePassed {
                ContextualTipBanner(
                    icon: "gavel",
                    message: uniqueGames < target
                        ? "Deadline passed with \(uniqueGames) of \(target) games. Fill the rest or open with fewer."
                        : "Deadline passed. Open the week when ready."
                )
                if uniqueGames < target {
                    PrimaryButton(title: "Fill Remaining Games", isLoading: viewModel.isLoadingGames) {
                        Task {
                            await viewModel.browseGames(appState: appState)
                        }
                    }
                }
                SecondaryButton("Open With \(uniqueGames) Game\(uniqueGames == 1 ? "" : "s")", icon: "lock.open.fill") {
                    viewModel.openWeekWithCurrentSlate(appState: appState)
                }
                .disabled(uniqueGames == 0)
                if uniqueGames == 0 {
                    Text("Add at least one Selection before opening the week.")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            } else {
                SecondaryButton("Open Week Early", icon: "lock.fill") {
                    viewModel.lockSlateEarly(appState: appState)
                }
                .disabled(uniqueGames == 0)
                if uniqueGames == 0 {
                    Text("Add at least one Selection before opening the week.")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
        }
        .padding(.horizontal)
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
    private func nominationSubmitSection(userNoms: Int, perMember: Int, week: WeekSummary) -> some View {
        if appState.pickService.didSubmitNominations {
            VStack(alignment: .leading, spacing: 8) {
                StatusBadge(text: "Submitted", color: PickemsColors.success)
                Text(SelectionPhaseCopy.submittedCaption(gameCount: userNoms, week: week))
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SecondaryButton("Edit Selections", icon: "pencil") {
                    viewModel.unlockSelectionsForEditing(appState: appState)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("You've selected your \(perMember) game\(perMember == 1 ? "" : "s"). Submit to lock in your Selections.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SelectionPhaseCopy.swapHint)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Submit Selections") {
                    viewModel.showConfirmNominations = true
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Picking

    private func pickingPhase(week: WeekSummary) -> some View {
        let pastDeadline = ScoringEngine.isPastDeadline(deadline: week.pickDeadline)
        let allowLate = group.rules.allowLatePicks
        let picksClosed = pastDeadline && !allowLate
        let slateGames = appState.pickService.slateGames

        return VStack(spacing: 16) {
            PickemsSectionHeader(
                title: "Spread Pickems",
                subtitle: "Tap a team to pick. Tap again to clear that Pickem — the Selection stays on the slate.",
                help: PickemsHelp.spreadPicks
            )

            if let deadline = week.pickDeadline {
                PickDeadlineBanner(deadline: deadline)
            }

            if appState.pickService.userPick?.isLocked == true {
                VStack(alignment: .leading, spacing: 8) {
                    StatusBadge(text: "Submitted", color: PickemsColors.success)
                    if !picksClosed {
                        Text("Submitted — you can edit until lock")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SecondaryButton("Edit Pickems", icon: "pencil") {
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
                    submissions: appState.pickService.submissions,
                    slateSize: appState.pickService.slateGames.count
                )

                SecondaryButton(
                    pastDeadline ? "Extend / Unlock Deadline" : "Set Pickems Deadline",
                    icon: "calendar.badge.clock"
                ) {
                    showPickDeadlineSheet = true
                }
                .padding(.horizontal)
            }

            if slateGames.isEmpty {
                ContentUnavailableView(
                    "Slate Not Ready",
                    systemImage: "sportscourt",
                    description: Text("Games will appear here once they're added to the slate.")
                )
                .padding(.top, 16)
            } else {
                let slateEditable = WeekTransition.isSlateEditable(week)
                ForEach(slateGames) { game in
                    VStack(spacing: 4) {
                        GamePickRow(
                            game: game,
                            selectedTeamId: viewModel.draftPicks[game.id],
                            isDisabled: appState.pickService.userPick?.isLocked == true || picksClosed,
                            showConfidenceToggle: group.rules.allowConfidencePick
                                && appState.pickService.userPick?.isLocked != true
                                && !picksClosed,
                            isConfidence: viewModel.confidenceGameId == game.id,
                            onConfidenceToggle: {
                                viewModel.confidenceGameId = viewModel.confidenceGameId == game.id ? nil : game.id
                                viewModel.saveDraft(appState: appState)
                            }
                        ) { teamId in
                            if teamId.isEmpty {
                                viewModel.draftPicks.removeValue(forKey: game.id)
                                if viewModel.confidenceGameId == game.id {
                                    viewModel.confidenceGameId = nil
                                }
                            } else {
                                viewModel.draftPicks[game.id] = teamId
                            }
                            viewModel.saveDraft(appState: appState)
                        }
                        if appState.isCommissioner && slateEditable {
                            HStack {
                                Button("Edit Spread") { viewModel.spreadEditGame = game }
                                    .font(.caption).foregroundStyle(theme.accent)
                                Spacer()
                                Button(role: .destructive) {
                                    viewModel.removeCommissionerGame(game, week: week, appState: appState)
                                } label: {
                                    Label("Remove Selection", systemImage: "trash").font(.caption)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if appState.pickService.userPick?.isLocked != true, !slateGames.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    PrimaryButton(title: groupPickingSubmitTitle(picksClosed: picksClosed, slateCount: slateGames.count)) {
                        handlePickingSubmit()
                    }
                    .disabled(picksClosed)

                    if hasIncompletePickems, !picksClosed {
                        Text(incompletePickemsCaption)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func groupPickingSubmitTitle(picksClosed: Bool, slateCount: Int) -> String {
        if picksClosed { return "Deadline Passed" }
        let count = viewModel.draftPicks.count
        if count == 0 { return "Make Pickems" }
        if count < slateCount { return "Finish Pickems (\(count)/\(slateCount))" }
        return "Submit Pickems"
    }

    private var hasIncompletePickems: Bool {
        let slate = appState.pickService.slateGames.count
        return slate > 0 && viewModel.draftPicks.count < slate
    }

    private var incompletePickemsCaption: String {
        let count = viewModel.draftPicks.count
        let slate = appState.pickService.slateGames.count
        return "You've picked \(count) of \(slate) games. Finish your Pickems to submit."
    }

    private func handlePickingSubmit() {
        if hasIncompletePickems {
            let count = viewModel.draftPicks.count
            let slate = appState.pickService.slateGames.count
            incompletePickemsAlertText = "You've picked \(count) of \(slate) games."
            showIncompletePickemsAlert = true
        } else {
            viewModel.showConfirmSubmit = true
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

            if appState.isCommissioner, week.status == .locked {
                SecondaryButton("Reopen Pickems", icon: "lock.open") {
                    showPickDeadlineSheet = true
                }
                .padding(.horizontal)
            }

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
                        subtitle: "Pickems with spreads",
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
                        initials: member.initials,
                        colorHex: member.avatarColorHex,
                        imageURL: member.avatarImageURL,
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
                    Text("No Pickems submitted")
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
        case .selection: return appState.isCommissioner ? "Build Slate" : "Make Selections"
        case .picking: return "Make Pickems"
        case .locked, .scored: return "Live Pickems"
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

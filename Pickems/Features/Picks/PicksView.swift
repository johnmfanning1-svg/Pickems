import SwiftUI

enum PicksWorkspaceKind {
    case selections
    case pickems
}

struct PicksView: View {
    var kind: PicksWorkspaceKind = .pickems
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var showSelectionDeadlineSheet = false
    @State private var showPickDeadlineSheet = false
    @State private var showIncompletePickemsAlert = false
    @State private var incompletePickemsAlertText = ""

    private var viewModel: PicksViewModel { appState.picksViewModel }

    private var showsGroupPicker: Bool {
        appState.groupService.groups.count > 1
    }

    var body: some View {
        @Bindable var viewModel = appState.picksViewModel
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if showsGroupPicker {
                        picksGroupPicker
                    }

                    if !appState.groupService.availableWeeks.isEmpty {
                        PicksWeekTabBar(
                            weeks: appState.groupService.availableWeeks,
                            selectedWeekId: appState.groupService.currentWeek?.id,
                            activeWeekId: activeESPNWeekId
                        ) { week in
                            selectWeek(week)
                        }
                    }

                    if let week = appState.groupService.currentWeek {
                        statusContent(for: week)
                    } else {
                        EmptyStateView(
                            icon: "sportscourt.fill",
                            title: "No Active Week",
                            message: kind == .selections
                                ? "Join a league to start making Selections."
                                : "Join a league to start making Pickems.",
                            help: kind == .selections ? PickemsHelp.nominations : PickemsHelp.picksOverview
                        )
                    }

                    if kind == .pickems, appState.groupService.selectedGroup != nil {
                        seasonHistoryControl
                    }

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
            .navigationTitle(kind == .selections ? "Selections" : "Pickems")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                HelpToolbarItem(topic: kind == .selections ? PickemsHelp.nominations : PickemsHelp.picksOverview)
            }
            .refreshable { await reloadPicks() }
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
                    if let week = appState.groupService.currentWeek {
                        viewModel.submitPicks(week: week, appState: appState)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can still edit your Pickems until the lock time shown on this week.")
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
                    weekLabel: appState.groupService.currentWeek?.displayLabel ?? "This week",
                    initialDeadline: appState.groupService.currentWeek?.selectionDeadline
                ) { deadline in
                    viewModel.setSelectionDeadline(deadline, appState: appState)
                }
                .pickemsEnvironment(appState)
            }
            .sheet(isPresented: $showPickDeadlineSheet) {
                if let week = appState.groupService.currentWeek {
                    PickDeadlineEditorSheet(
                        weekLabel: week.displayLabel,
                        weekStatus: week.status,
                        initialDeadline: week.pickDeadline,
                        isPastDeadline: PickDeadlineCalculator.isPast(week.pickDeadline)
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
            }
            .onChange(of: appState.pendingSelectionDeadlinePrompt) { _, pending in
                if pending, kind == .selections, appState.isCommissioner,
                   appState.groupService.currentWeek?.status == .selection {
                    showSelectionDeadlineSheet = true
                    appState.pendingSelectionDeadlinePrompt = false
                }
            }
            .task(id: appState.groupService.selectedGroup?.id) {
                await reloadPicks()
            }
            .onChange(of: appState.groupService.currentWeek?.id) { _, newWeekId in
                reobservePicks(weekId: newWeekId)
                viewModel.refreshNominationSubmissionState(appState: appState)
            }
            .syncPicksDraftFromServer()
            .onChange(of: appState.selectedTab) { _, tab in
                if tab == .selections || tab == .pickems {
                    viewModel.resyncWhenVisible(appState: appState)
                }
            }
        }
    }

    // MARK: - Group / week chrome

    private var picksGroupPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Leagues")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(appState.groupService.groups) { group in
                        GroupChip(
                            name: group.name,
                            isSelected: appState.groupService.selectedGroup?.id == group.id
                        ) {
                            PickemsHaptics.selection()
                            appState.groupService.selectGroup(group)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var seasonHistoryControl: some View {
        NavigationLink { SeasonPickHistoryView() } label: {
            Label("Season History", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal)
        .accessibilityHint("Review your Pickems across the season")
    }

    private var activeESPNWeekId: String? {
        appState.groupService.cfbWeek.map { CFBWeekSync.weekId(for: $0) }
            ?? appState.groupService.currentWeek?.id
    }

    private func selectWeek(_ week: WeekSummary) {
        PickemsHaptics.selection()
        viewModel.stopLiveRefresh()
        viewModel.resetPendingWrite()
        viewModel.draftPicks = [:]
        viewModel.confidenceGameId = nil
        appState.groupService.selectWeek(weekId: week.id)
        reobservePicks(weekId: week.id)
    }

    private func reobservePicks(weekId: String?) {
        guard let group = appState.groupService.selectedGroup,
              let weekId,
              let userId = appState.currentUserId else { return }
        appState.pickService.observeWeek(groupId: group.id, weekId: weekId, userId: userId)
        viewModel.syncDraftFromServer(
            appState.pickService.userPick?.picks,
            confidenceGameId: appState.pickService.userPick?.confidenceGameId
        )
        viewModel.refreshNominationSubmissionState(appState: appState)
    }

    private func reloadPicks() async {
        await viewModel.loadWeek(appState: appState)
        if let groupId = appState.groupService.selectedGroup?.id {
            await appState.groupService.loadAvailableWeeks(groupId: groupId)
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private func statusContent(for week: WeekSummary) -> some View {
        switch kind {
        case .selections:
            if let deadline = week.selectionDeadline {
                SelectionDeadlineBanner(deadline: deadline)
            } else if week.status == .selection, appState.isCommissioner {
                ContextualTipBanner(
                    icon: "bell.badge",
                    message: "Set a Selection deadline so members finish before kickoff."
                )
                .padding(.horizontal)
            }
            if week.status == .selection {
                selectionPhase(week: week)
                GroupPicksView(embedded: true, forceNominatingDisplay: true)
                    .padding(.top, 8)
            } else {
                ContextualTipBanner(
                    icon: "lock.fill",
                    message: "Selections are locked. Pickems are on the Pickems tab."
                )
                .padding(.horizontal)
                GroupPicksView(embedded: true, forceNominatingDisplay: true)
            }
        case .pickems:
            if WeekTransition.arePickemsOpen(week) {
                if let deadline = week.pickDeadline {
                    PickDeadlineBanner(deadline: deadline)
                }
                switch week.status {
                case .picking: pickingPhase(week: week)
                case .locked, .scored: lockedPhase(week: week)
                case .selection: EmptyView()
                }
            } else {
                ContextualTipBanner(
                    icon: "lock.fill",
                    message: "Pickems open when every Selection is in or the Selection deadline passes. Your commissioner can lock early."
                )
                .padding(.horizontal)
                pickingPhase(week: week)
                    .disabled(true)
                    .opacity(0.45)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Pickems locked until Selections are complete")
            }
        }
    }

    @ViewBuilder
    private func selectionPhase(week: WeekSummary) -> some View {
        let rules = appState.groupService.selectedGroup?.rules ?? .default
        let mode = week.selectionMode
        if mode == .commissioner && appState.isCommissioner {
            commissionerSelectionUI(week: week, rules: rules)
        } else if mode == .member {
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
        let memberCount = max(appState.groupService.selectedGroup?.memberCount ?? 1, 1)
        let target = rules.expectedSlateSize(memberCount: memberCount)
        return VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Make Selections",
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

    private func memberNominationUI(week: WeekSummary, rules: GroupRules) -> some View {
        let userId = appState.currentUserId ?? ""
        let perMember = week.selectionsPerMember > 0 ? week.selectionsPerMember : rules.selectionsPerMember
        let userNoms = appState.pickService.nominations.filter { $0.submittedBy == userId }.count
        let atLimit = userNoms >= perMember
        let memberIds = appState.groupService.selectedGroup?.memberIds ?? []
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

        return VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Make Selections",
                subtitle: "You: \(userNoms)/\(perMember) · Members done: \(membersDone)/\(memberCount) · Games: \(uniqueGames)/\(targetGames)",
                help: PickemsHelp.nominations
            )

            if appState.isCommissioner {
                picksCommissionerSelectionControls(
                    week: week,
                    uniqueGames: uniqueGames,
                    deadlinePassed: deadlinePassed
                )
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
                EmptyView()
            } else if atLimit {
                nominationSubmitSection(userNoms: userNoms, perMember: perMember, week: week)
            } else if !deadlinePassed {
                PrimaryButton(title: "Select Game", isLoading: viewModel.isLoadingGames) {
                    Task {
                        await viewModel.browseGames(appState: appState)
                    }
                }
                .padding(.horizontal)
            }

            ForEach(appState.pickService.nominations) { nom in
                PickemsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(nom.awayTeamName) @ \(nom.homeTeamName)")
                            Text(nominationSpreadLabel(nom))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.accent)
                            Text("by \(nom.submitterName)").font(.caption).foregroundStyle(PickemsColors.textSecondary)
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

    @ViewBuilder
    private func picksCommissionerSelectionControls(
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
                SecondaryButton("Edit Selection Deadline", icon: "calendar") {
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
        // Favorite (spreadTeamId) always shows as -line, matching SlateGame.spreadLabel.
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

    private func pickingPhase(week: WeekSummary) -> some View {
        let pastDeadline = PickDeadlineCalculator.isPast(week.pickDeadline)
        let allowLate = appState.groupService.selectedGroup?.rules.allowLatePicks == true
        let picksClosed = pastDeadline && !allowLate

        return VStack(spacing: 16) {
            PickemsSectionHeader(title: "Spread Pickems", subtitle: "Tap a team to pick. Tap again to clear that Pickem — the Selection stays on the slate.", help: PickemsHelp.spreadPicks)

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

            let slateEditable = WeekTransition.isSlateEditable(week)
            ForEach(appState.pickService.slateGames) { game in
                VStack(spacing: 4) {
                    GamePickRow(
                        game: game,
                        selectedTeamId: viewModel.draftPicks[game.id],
                        isDisabled: appState.pickService.userPick?.isLocked == true || picksClosed,
                        showConfidenceToggle: appState.groupService.selectedGroup?.rules.allowConfidencePick == true
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

            if appState.pickService.userPick?.isLocked != true {
                VStack(alignment: .leading, spacing: 8) {
                    PrimaryButton(title: pickingSubmitTitle(picksClosed: picksClosed)) {
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

    private func pickingSubmitTitle(picksClosed: Bool) -> String {
        if picksClosed { return "Deadline Passed" }
        let count = viewModel.draftPicks.count
        let slate = appState.pickService.slateGames.count
        if count == 0 { return "Make Pickems" }
        if slate > 0, count < slate { return "Finish Pickems (\(count)/\(slate))" }
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

    private func lockedPhase(week: WeekSummary) -> some View {
        VStack(spacing: 12) {
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

            NavigationLink { GroupPicksView() } label: {
                Label("View League Pickems", systemImage: "person.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(theme.accent)
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

// MARK: - Week tabs

private struct PicksWeekTabBar: View {
    @Environment(\.themePalette) private var theme
    let weeks: [WeekSummary]
    let selectedWeekId: String?
    let activeWeekId: String?
    let onSelect: (WeekSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(weeks) { week in
                            weekTab(week)
                                .id(week.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onAppear { scrollToSelected(proxy) }
                .onChange(of: selectedWeekId) { _, _ in scrollToSelected(proxy) }
                .onChange(of: weeks.map(\.id)) { _, _ in scrollToSelected(proxy) }
            }
        }
    }

    private func weekTab(_ week: WeekSummary) -> some View {
        let isSelected = week.id == selectedWeekId
        let isActive = week.id == activeWeekId
        return Button {
            onSelect(week)
        } label: {
            VStack(spacing: 2) {
                Text("Week \(week.weekNumber)")
                    .font(.subheadline.weight(.semibold))
                if isActive {
                    Text("Current")
                        .font(.caption2.weight(.medium))
                        .opacity(isSelected ? 0.9 : 0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? theme.accent : PickemsColors.cardBackground)
            .foregroundStyle(isSelected ? theme.onAccent : PickemsColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(week.weekNumber)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isActive ? "Current week" : "View Pickems for this week")
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy) {
        guard let selectedWeekId else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(selectedWeekId, anchor: .center)
            }
        }
    }
}

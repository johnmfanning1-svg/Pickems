import SwiftUI

enum PicksWorkspaceKind {
    case selections
    case pickems
}

struct PicksView: View {
    var kind: PicksWorkspaceKind = .pickems
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var showIncompletePickemsAlert = false
    @State private var incompletePickemsAlertText = ""
    @State private var isRefreshing = false
    @State private var picksExpanded = false

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

                    if !displayedWeeks.isEmpty {
                        PicksWeekTabBar(
                            weeks: displayedWeeks,
                            selectedWeekId: workspaceWeek?.id,
                            activeWeekId: activeESPNWeekId,
                            dateRangeLabel: { appState.groupService.dateRangeLabel(for: $0.id) }
                        ) { week in
                            selectWeek(week)
                        }
                    }

                    if let week = workspaceWeek {
                        statusContent(for: week)
                    } else {
                        noActiveWeekEmptyState
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
            .pickemsRefreshable(isRefreshing: $isRefreshing) {
                await reloadPicks()
            }
            .alert("Submit your Pickems?", isPresented: $viewModel.showConfirmSubmit) {
                Button("Submit Pickems") {
                    if let week = appState.groupService.currentWeek {
                        viewModel.submitPicks(week: week, appState: appState)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(workspaceWeek?.isRollingLock == true
                    ? "You can still edit until each game kicks off."
                    : "You can still edit your Pickems until the lock time shown on this week.")
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
            .task(id: appState.groupService.selectedGroup?.id) {
                await reloadPicks()
            }
            .onChange(of: appState.groupService.currentWeek?.id) { _, newWeekId in
                picksExpanded = false
                reobservePicks(weekId: newWeekId)
                viewModel.refreshNominationSubmissionState(appState: appState)
            }
            .syncPicksDraftFromServer()
            .onChange(of: appState.selectedTab) { oldTab, tab in
                if kind == .selections, oldTab == .selections, tab != .selections {
                    snapToActiveWeek()
                    return
                }
                guard isThisWorkspace(tab) else { return }
                viewModel.resyncWhenVisible(appState: appState)
                snapToActiveWeek()
            }
        }
    }

    private var noActiveWeekEmptyState: some View {
        EmptyStateView(
            icon: kind == .selections ? "american.football.fill" : "checkmark.circle.fill",
            title: "No Active Week",
            message: kind == .selections
                ? "Join a league to start making Selections."
                : "Join a league to start making Pickems.",
            help: kind == .selections ? PickemsHelp.nominations : PickemsHelp.picksOverview
        )
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
        .accessibilityHint("View league Pickems charts by week")
    }

    private var displayedWeeks: [WeekSummary] {
        let weeks = appState.groupService.availableWeeks
        if kind == .pickems {
            return weeks.filter { !appState.groupService.isFutureWeek($0) }
        }
        return weeks
    }

    private var workspaceWeek: WeekSummary? {
        PicksDisplayedWeek.resolve(
            current: appState.groupService.currentWeek,
            hideFuture: kind == .pickems,
            available: appState.groupService.availableWeeks,
            activeWeekId: activeESPNWeekId,
            isFuture: { appState.groupService.isFutureWeek($0) }
        )
    }

    private var activeESPNWeekId: String? {
        appState.groupService.cfbWeek.map { CFBWeekSync.weekId(for: $0) }
            ?? appState.groupService.currentWeek?.id
    }

    private func isThisWorkspace(_ tab: AppTab) -> Bool {
        (kind == .selections && tab == .selections) || (kind == .pickems && tab == .pickems)
    }

    private func picksMatchWeek(_ week: WeekSummary) -> Bool {
        appState.pickService.observedWeekId == week.id
    }

    /// Unpin and re-observe on this turn so the next frame isn't the browsed week.
    private func snapToActiveWeek() {
        viewModel.stopLiveRefresh()
        viewModel.resetPendingWrite()
        viewModel.draftPicks = [:]
        viewModel.confidenceGameId = nil
        appState.groupService.unpinToActiveWeekLocally()
        reobservePicks(weekId: appState.groupService.currentWeek?.id)
        viewModel.resyncWhenVisible(appState: appState)
        Task { await appState.groupService.jumpToActiveWeek() }
    }

    private func selectWeek(_ week: WeekSummary) {
        if kind == .pickems, appState.groupService.isFutureWeek(week) {
            return
        }
        PickemsHaptics.selection()
        viewModel.stopLiveRefresh()
        viewModel.resetPendingWrite()
        viewModel.draftPicks = [:]
        viewModel.confidenceGameId = nil
        Task {
            await appState.groupService.selectWeek(weekId: week.id)
            reobservePicks(weekId: week.id)
        }
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
        await appState.refreshLeagueData()
        await viewModel.loadWeek(appState: appState)
        await viewModel.ensureTeamRanks(appState: appState)
        await viewModel.refreshLiveNow(appState: appState, forceRefresh: true)
    }

    // MARK: - Phase content

    @ViewBuilder
    private func statusContent(for week: WeekSummary) -> some View {
        switch kind {
        case .selections:
            if week.skipsSelection {
                EmptyStateView(
                    icon: "checkmark.circle.fill",
                    title: "Slate is set",
                    message: "Week 0 is the eight Saturday openers. Head to Pickems to make your picks."
                )
                PrimaryButton(title: "Make Pickems") {
                    appState.selectedTab = .pickems
                }
                .padding(.horizontal)
            } else if let deadline = week.selectionDeadline {
                SelectionDeadlineBanner(deadline: deadline)
            } else if week.status == .selection, appState.isCommissioner {
                ContextualTipBanner(
                    icon: "gearshape.fill",
                    message: "Set the Selection deadline and other weekly admin in Commissioner Settings."
                )
                .padding(.horizontal)
            }
            if week.skipsSelection {
                EmptyView()
            } else if !picksMatchWeek(week) {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .accessibilityLabel("Loading this week's Selections")
            } else if week.status == .selection {
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
                if !WeekTransition.pickemsShouldShowFullLockedPhase(week) {
                    pickemsLockBanner(for: week)
                    if picksMatchWeek(week) {
                        SecondaryButton("See who's in", icon: "person.crop.circle.badge.clock") {
                            appState.present(.submissionStatus)
                        }
                        .padding(.horizontal)
                        .accessibilityHint("Shows how many Pickems each member has made, without revealing their picks")
                    }
                }
                pickemsGames(for: week)
            } else {
                ContextualTipBanner(
                    icon: "lock.fill",
                    message: "Pickems open when every Selection is in or the Selection deadline passes. Your commissioner can lock early."
                )
                .padding(.horizontal)
                if picksMatchWeek(week) {
                    pickingPhase(week: week)
                        .disabled(true)
                        .opacity(0.45)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Pickems locked until Selections are complete")
                }
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
                subtitle: "\(appState.pickService.displaySlateGames.count) of \(target) games selected",
                help: PickemsHelp.commissionerSlate
            )

            PrimaryButton(title: "Add Game") {
                viewModel.selectionBrowseIntent = .own
                appState.present(.gameBrowse)
            }
            .padding(.horizontal)

            SecondaryButton("Bulk Import Scheduled", icon: "square.stack.3d.up.fill") {
                Task { await viewModel.bulkImportScheduled(week: week, rules: rules, appState: appState) }
            }
            .padding(.horizontal)

            Text("Games are listed by person below. Edit spreads in Commissioner Settings.")
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
                .padding(.horizontal)
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

            if deadlinePassed, !appState.isCommissioner {
                EmptyView()
            } else if atLimit {
                nominationSubmitSection(userNoms: userNoms, perMember: perMember, week: week)
            } else if WeekTransition.canRemakeSelections(week) {
                PrimaryButton(title: "Select Game") {
                    viewModel.selectionBrowseIntent = .own
                    appState.present(.gameBrowse)
                }
                .padding(.horizontal)
            }
        }
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
                if WeekTransition.canRemakeSelections(week) {
                    SecondaryButton("Edit Selections", icon: "pencil") {
                        viewModel.unlockSelectionsForEditing(appState: appState)
                    }
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

    @ViewBuilder
    private func pickemsLockBanner(for week: WeekSummary) -> some View {
        let games = appState.pickService.slateGames
        if let next = PickDeadlineCalculator.nextLockDate(week: week, games: games) {
            PickDeadlineBanner(
                deadline: next,
                isRolling: week.isRollingLock,
                openCount: PickDeadlineCalculator.openGameCount(week: week, games: games),
                totalCount: games.count
            )
        } else if let deadline = week.pickDeadline {
            PickDeadlineBanner(deadline: deadline)
        }
    }

    @ViewBuilder
    private func pickemsGames(for week: WeekSummary) -> some View {
        if picksMatchWeek(week) {
            if WeekTransition.pickemsShouldShowFullLockedPhase(week) {
                lockedPhase(week: week)
            } else if week.status != .selection {
                pickingPhase(week: week)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityLabel("Loading this week's Pickems")
        }
    }

    private func pickingPhase(week: WeekSummary) -> some View {
        let rolling = week.isRollingLock
        let fullyLocked = WeekTransition.arePicksFullyLocked(week)
        let allowLate = !rolling && appState.groupService.selectedGroup?.rules.allowLatePicks == true
        let picksClosed = fullyLocked && !allowLate
        let submittedFrozen = !rolling && appState.pickService.userPick?.isLocked == true
        let games = appState.pickService.slateGames.sortedByKickoff
        let openGames = games.filter { !WeekTransition.isGameLocked($0, week: week) }

        return VStack(spacing: 16) {
            PickemsSectionHeader(title: "Spread Pickems", subtitle: "Tap a team to pick. Tap again to clear that Pickem — the Selection stays on the slate.", help: PickemsHelp.spreadPicks)

            if appState.pickService.userPick?.isLocked == true {
                VStack(alignment: .leading, spacing: 8) {
                    StatusBadge(text: "Submitted", color: PickemsColors.success)
                    if !picksClosed {
                        Text(rolling
                            ? "You can edit games that haven’t started"
                            : "Submitted — you can edit until lock")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !rolling {
                            SecondaryButton("Edit Pickems", icon: "pencil") {
                                viewModel.unlockPicksForEditing(appState: appState)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }

            ForEach(games) { game in
                let gameLocked = WeekTransition.isGameLocked(game, week: week)
                GamePickRow(
                    game: game,
                    selectedTeamId: viewModel.draftPicks[game.id],
                    isDisabled: submittedFrozen || picksClosed || gameLocked,
                    liveCard: viewModel.livePickCards[game.espnEventId],
                    homeRank: viewModel.teamRanks.rank(for: game.homeTeamId),
                    awayRank: viewModel.teamRanks.rank(for: game.awayTeamId),
                    showConfidenceToggle: appState.groupService.selectedGroup?.rules.allowConfidencePick == true
                        && !submittedFrozen
                        && !picksClosed
                        && !gameLocked,
                    isConfidence: viewModel.confidenceGameId == game.id,
                    onConfidenceToggle: {
                        viewModel.confidenceGameId = viewModel.confidenceGameId == game.id ? nil : game.id
                        viewModel.saveDraft(appState: appState)
                    },
                    lockedCaption: gameLocked ? "Locked at kickoff" : nil
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
                .padding(.horizontal)
            }

            if rolling, WeekTransition.pickemsShouldShowLeagueBoard(week) {
                GroupPicksView(embedded: true)
            }

            if appState.pickService.userPick?.isLocked != true {
                VStack(alignment: .leading, spacing: 8) {
                    PrimaryButton(title: pickingSubmitTitle(picksClosed: picksClosed, openGames: openGames)) {
                        handlePickingSubmit(openGames: openGames)
                    }
                    .disabled(picksClosed)

                    if hasIncompletePickems(openGames: openGames), !picksClosed {
                        Text(incompletePickemsCaption(openGames: openGames))
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func pickingSubmitTitle(picksClosed: Bool, openGames: [SlateGame]) -> String {
        if picksClosed { return "Deadline Passed" }
        let openIds = Set(openGames.map(\.id))
        let openPicked = viewModel.draftPicks.keys.filter { openIds.contains($0) }.count
        let openTotal = openGames.count
        let slate = appState.pickService.slateGames.count
        if openTotal < slate {
            if openPicked == 0 { return "Make remaining Pickems" }
            if openTotal > 0, openPicked < openTotal {
                return "Submit remaining (\(openPicked)/\(openTotal) open)"
            }
            return "Submit remaining Pickems"
        }
        if openPicked == 0 { return "Make Pickems" }
        if slate > 0, openPicked < slate { return "Finish Pickems (\(openPicked)/\(slate))" }
        return "Submit Pickems"
    }

    private func hasIncompletePickems(openGames: [SlateGame]) -> Bool {
        let openIds = Set(openGames.map(\.id))
        guard !openIds.isEmpty else { return false }
        return openIds.contains { viewModel.draftPicks[$0] == nil }
    }

    private func incompletePickemsCaption(openGames: [SlateGame]) -> String {
        let openIds = Set(openGames.map(\.id))
        let openPicked = viewModel.draftPicks.keys.filter { openIds.contains($0) }.count
        if openGames.count < appState.pickService.slateGames.count {
            return "You've picked \(openPicked) of \(openGames.count) open games. Finish remaining Pickems to submit."
        }
        return "You've picked \(openPicked) of \(openGames.count) games. Finish your Pickems to submit."
    }

    private func handlePickingSubmit(openGames: [SlateGame]) {
        if hasIncompletePickems(openGames: openGames) {
            let openIds = Set(openGames.map(\.id))
            let openPicked = viewModel.draftPicks.keys.filter { openIds.contains($0) }.count
            incompletePickemsAlertText = "You've picked \(openPicked) of \(openGames.count) open games."
            showIncompletePickemsAlert = true
        } else {
            viewModel.showConfirmSubmit = true
        }
    }

    private func lockedPhase(week: WeekSummary) -> some View {
        VStack(spacing: 16) {
            GroupPicksView(embedded: true)

            yourPickemsDisclosure(week: week)
        }
        .task(id: week.id) {
            if let group = appState.groupService.selectedGroup {
                await appState.pickService.loadAllPicks(groupId: group.id, weekId: week.id)
            }
            await viewModel.ensureTeamRanks(appState: appState)
            viewModel.startLiveRefresh(week: week, appState: appState)
        }
        .onDisappear { viewModel.stopLiveRefresh() }
    }

    private func yourPickemsDisclosure(week: WeekSummary) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    picksExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Pickems")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PickemsColors.textPrimary)
                        Text(week.status == .scored ? "Final results" : "Locked for this week")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }

                    Spacer(minLength: 8)

                    StatusBadge(
                        text: week.status == .scored ? "Scored" : "Locked",
                        color: week.status == .scored ? PickemsColors.success : PickemsColors.textSecondary
                    )

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .rotationEffect(.degrees(picksExpanded ? 0 : -90))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(PickemsColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your Pickems")
            .accessibilityValue(picksExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(picksExpanded ? "Hides your Pickems" : "Shows your Pickems")
            .accessibilityAddTraits(.isButton)

            if picksExpanded {
                VStack(spacing: 8) {
                    ForEach(appState.pickService.slateGames.sortedByKickoff) { game in
                        GamePickRow(
                            game: game,
                            selectedTeamId: viewModel.draftPicks[game.id],
                            isDisabled: true,
                            liveCard: viewModel.livePickCards[game.espnEventId],
                            homeRank: viewModel.teamRanks.rank(for: game.homeTeamId),
                            awayRank: viewModel.teamRanks.rank(for: game.awayTeamId),
                            onSelect: { _ in }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Week tabs

private struct PicksWeekTabBar: View {
    @Environment(\.themePalette) private var theme
    let weeks: [WeekSummary]
    let selectedWeekId: String?
    let activeWeekId: String?
    let dateRangeLabel: (WeekSummary) -> String?
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
                if let range = dateRangeLabel(week), !range.isEmpty {
                    Text(range)
                        .font(.caption2.weight(.medium))
                        .opacity(isSelected ? 0.9 : 0.7)
                }
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
        .accessibilityLabel(accessibilityLabel(for: week))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isActive ? "Current week" : "View this week")
    }

    private func accessibilityLabel(for week: WeekSummary) -> String {
        if let range = dateRangeLabel(week), !range.isEmpty {
            return "Week \(week.weekNumber), \(range)"
        }
        return "Week \(week.weekNumber)"
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

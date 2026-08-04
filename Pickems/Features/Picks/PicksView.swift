import SwiftUI

struct PicksView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var viewModel = PicksViewModel()

    private var showsGroupPicker: Bool {
        appState.groupService.groups.count > 1
    }

    var body: some View {
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
                            message: "Join a group to start making picks.",
                            help: PickemsHelp.picksOverview
                        )
                    }

                    if appState.groupService.selectedGroup != nil {
                        seasonHistoryControl
                    }

                    if let error = appState.pickService.errorMessage {
                        ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                    }
                }
                .padding(.vertical)
            }
            .pickemsScreenBackground()
            .navigationTitle("Picks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HelpToolbarButton(topic: PickemsHelp.picksOverview)
                }
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
            .confirmationDialog("Submit your picks?", isPresented: $viewModel.showConfirmSubmit, titleVisibility: .visible) {
                Button("Submit Picks") {
                    if let week = appState.groupService.currentWeek {
                        viewModel.submitPicks(week: week, appState: appState)
                    }
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
            .task(id: appState.groupService.selectedGroup?.id) {
                await reloadPicks()
            }
            .onChange(of: appState.groupService.currentWeek?.id) { _, newWeekId in
                reobservePicks(weekId: newWeekId)
                viewModel.refreshNominationSubmissionState(appState: appState)
            }
            .onChange(of: appState.pickService.userPick?.picks) { _, newPicks in
                viewModel.syncDraftFromServer(newPicks, confidenceGameId: appState.pickService.userPick?.confidenceGameId)
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
        .accessibilityHint("Review your picks across the season")
    }

    private var activeESPNWeekId: String? {
        appState.groupService.cfbWeek.map { CFBWeekSync.weekId(for: $0) }
            ?? appState.groupService.currentWeek?.id
    }

    private func selectWeek(_ week: WeekSummary) {
        PickemsHaptics.selection()
        viewModel.stopLiveRefresh()
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
        if let picks = appState.pickService.userPick?.picks, !picks.isEmpty {
            viewModel.draftPicks = picks
        }
        viewModel.confidenceGameId = appState.pickService.userPick?.confidenceGameId
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

    private func pickingPhase(week: WeekSummary) -> some View {
        let pastDeadline = PickDeadlineCalculator.isPast(week.pickDeadline)

        return VStack(spacing: 16) {
            PickemsSectionHeader(title: "Spread Picks", subtitle: "Tap a team to pick against the spread", help: PickemsHelp.spreadPicks)

            if let deadline = week.pickDeadline {
                PickDeadlineBanner(deadline: deadline)
            }

            if appState.pickService.userPick?.isLocked == true {
                VStack(alignment: .leading, spacing: 8) {
                    StatusBadge(text: "Submitted", color: PickemsColors.success)
                    if !pastDeadline {
                        Text("Submitted — you can edit until lock")
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

            ForEach(appState.pickService.slateGames) { game in
                VStack(spacing: 4) {
                    GamePickRow(
                        game: game,
                        selectedTeamId: viewModel.draftPicks[game.id],
                        isDisabled: appState.pickService.userPick?.isLocked == true || pastDeadline,
                        showConfidenceToggle: appState.groupService.selectedGroup?.rules.allowConfidencePick == true
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

            NavigationLink { GroupPicksView() } label: {
                Label("View Group Picks", systemImage: "person.3")
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
        .accessibilityHint(isActive ? "Current week" : "View picks for this week")
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

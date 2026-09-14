import SwiftUI

/// Weekly commissioner tools. These used to live on Selections / Pickems / Leagues.
struct CommissionerWeekAdminSections: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    @Binding var showSelectionDeadlineSheet: Bool
    @Binding var showPickDeadlineSheet: Bool
    @Binding var showAdminGameBrowse: Bool
    @State private var showReopenSelectionsConfirm = false
    @State private var showPickModeConfirm = false
    @State private var pendingStraightUp = false
    @State private var rankDraft: TieRankDraft?

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
            .task {
                if let groupId = appState.groupService.selectedGroup?.id {
                    await appState.groupService.loadAvailableWeeks(groupId: groupId)
                }
                await picksVM.ensureTeamRanks(appState: appState)
            }
            .sheet(item: $rankDraft) { draft in
                CommissionerRankTiesSheet(
                    weekLabel: week?.displayLabel ?? "This week",
                    entries: draft.entries
                ) { orderedIds in
                    guard let groupId = appState.groupService.selectedGroup?.id,
                          let weekId = week?.id else {
                        throw GroupService.GroupError.groupNotFound
                    }
                    try await appState.groupService.resolveTieGroup(
                        groupId: groupId,
                        weekId: weekId,
                        orderedUserIds: orderedIds
                    )
                }
                .pickemsEnvironment(appState)
            }
        selectionsAdminSection
        slateSection
        pickemsAdminSection
        tiesSection
    }

    private var displayedWeeks: [WeekSummary] {
        appState.groupService.availableWeeks
    }

    private var activeESPNWeekId: String? {
        appState.groupService.cfbWeek.map { CFBWeekSync.weekId(for: $0) }
            ?? appState.groupService.currentWeek?.id
    }

    @ViewBuilder
    private var weekStatusSection: some View {
        Section {
            if !displayedWeeks.isEmpty {
                WeekChipBar(
                    weeks: displayedWeeks,
                    selectedWeekId: week?.id,
                    activeWeekId: activeESPNWeekId,
                    dateRangeLabel: { appState.groupService.dateRangeLabel(for: $0.id) },
                    accessibilityHint: "Admin this week. Also switches Selections and Pickems.",
                    showsCaption: false,
                    horizontalPadding: 0
                ) { selected in
                    selectAdminWeek(selected)
                }
                .buttonStyle(.borderless)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let week {
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
                                appState.picksViewModel.selectionBrowseIntent = .own
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

                weekPickModeRow(week)
            } else if displayedWeeks.isEmpty {
                Text("No active week.")
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("This Week")
        } footer: {
            Text("Deadlines, slate, Pickems, and ties for the week you pick. Switching here also switches Selections and Pickems. ATS leagues can score a future week — or this week before lock — Straight Up.")
        }
        .alert("Reopen Selections?", isPresented: $showReopenSelectionsConfirm) {
            Button("Reopen Selections") {
                picksVM.reopenSelections(appState: appState)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Members can add and remove Selections again. Pickems close until you open the week.")
        }
        .alert(pickModeConfirmTitle, isPresented: $showPickModeConfirm) {
            Button(pendingStraightUp ? "Score Straight Up" : "Use Spreads", role: .destructive) {
                applyPendingWeekPickMode()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(pickModeConfirmMessage)
        }
    }

    private func selectAdminWeek(_ selected: WeekSummary) {
        guard selected.id != week?.id else { return }
        PickemsHaptics.selection()
        appState.selectObservedWeek(selected)
    }

    @ViewBuilder
    private func weekPickModeRow(_ week: WeekSummary) -> some View {
        let leagueMode = appState.groupService.selectedGroup?.rules.pickMode ?? .ats
        let resolved = week.resolvedPickMode(leagueMode: leagueMode)
        if leagueMode == .ats {
            if WeekTransition.canChangeWeekPickMode(week, leagueMode: leagueMode) {
                Toggle("Straight Up this week", isOn: weekStraightUpBinding(week, resolved: resolved))
                    .listRowBackground(PickemsColors.cardBackground)
                    .accessibilityHint("Hide spreads and grade outright winners for this week only.")
            } else if resolved == .straightUp {
                LabeledContent("This week", value: PickMode.straightUp.displayName)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        }
    }

    private func weekStraightUpBinding(_ week: WeekSummary, resolved: PickMode) -> Binding<Bool> {
        Binding(
            get: { resolved == .straightUp },
            set: { newValue in
                guard newValue != (resolved == .straightUp) else { return }
                if WeekTransition.weekPickModeChangeResetsWork(
                    week,
                    nominationCount: week.nominationCount,
                    hasSlateOrPicks: hasWeekWork
                ) {
                    pendingStraightUp = newValue
                    showPickModeConfirm = true
                } else {
                    picksVM.setWeekPickMode(newValue ? .straightUp : nil, resetWork: false, appState: appState)
                }
            }
        )
    }

    private var hasWeekWork: Bool {
        !appState.pickService.nominations.isEmpty
            || !appState.pickService.slateGames.isEmpty
            || appState.pickService.userPick != nil
            || !appState.pickService.submissions.isEmpty
            || !appState.pickService.allPicks.isEmpty
    }

    private var pickModeConfirmTitle: String {
        if week?.skipsSelection == true {
            return pendingStraightUp ? "Clear this week's Pickems?" : "Clear Pickems and restore spreads?"
        }
        return pendingStraightUp ? "Reset this week's Selections?" : "Reset Selections and restore spreads?"
    }

    private var pickModeConfirmMessage: String {
        if week?.skipsSelection == true {
            return "The Week 0 slate stays. Everyone's Pickems for this week are cleared so they can pick again."
        }
        return "This week already has Selections or Pickems. Changing scoring resets them. Members will need to select games and make Pickems again."
    }

    private func applyPendingWeekPickMode() {
        picksVM.setWeekPickMode(
            pendingStraightUp ? .straightUp : nil,
            resetWork: true,
            appState: appState
        )
    }

    private func tieGroupTitle(_ group: [StandingEntry]) -> String {
        let count = group.count
        let records = Set(group.map { "\($0.weeklyWins)–\($0.weeklyLosses)" })
        if records.count == 1, let record = records.first {
            return "\(count) tied at \(record)"
        }
        let wins = group.first?.weeklyWins ?? 0
        return "\(count) tied at \(wins) win\(wins == 1 ? "" : "s")"
    }

    private func rollingPickDeadlineButtonTitle(_ week: WeekSummary) -> String {
        let fullyLocked = WeekTransition.arePicksFullyLocked(week)
        if week.isRollingLock {
            return fullyLocked ? "Lock remaining / Reopen" : "Lock remaining games"
        }
        return fullyLocked ? "Extend / Unlock Deadline" : "Set Pickems Deadline"
    }

    @ViewBuilder
    private var selectionsAdminSection: some View {
        if let week, WeekTransition.commissionerCanManageSelections(week),
           week.selectionMode == .member,
           let groupId = appState.groupService.selectedGroup?.id {
            Section {
                ForEach(appState.groupService.members) { member in
                    let progress = SubmissionRoster.selectionProgress(
                        nominations: appState.pickService.nominations,
                        memberId: member.id,
                        perMember: selectionsPerMember
                    )
                    NavigationLink {
                        CommissionerManageSelectionsSheet(
                            member: member,
                            week: week,
                            groupId: groupId
                        )
                    } label: {
                        memberProgressLabel(
                            name: member.displayName,
                            made: progress.made,
                            total: progress.total,
                            status: progress.status,
                            unitName: "Selections"
                        )
                    }
                    .accessibilityLabel(
                        "\(member.displayName), \(progress.made) of \(progress.total) Selections, \(progress.status.label). Manage Selections."
                    )
                    .listRowBackground(PickemsColors.cardBackground)
                }
            } header: {
                Text("Selections Admin")
            } footer: {
                Text("Tap a member to change their Selections. Counts are games submitted versus the weekly requirement.")
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
                        if appState.selectedPickMode.showsSpreads {
                            LockedSpreadLabel(
                                lockedText: game.favoriteSpreadDisplay,
                                liveText: picksVM.livePickCards[game.espnEventId]?.liveSpreadLabel
                            )
                        }
                        HStack {
                            if appState.selectedPickMode.showsSpreads {
                                Button("Edit Spread") { picksVM.spreadEditGame = game }
                            }
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
                Text(appState.selectedPickMode.showsSpreads
                    ? "Edit lines or remove a Selection. Members remake their own Selections on the Selections tab before the deadline."
                    : "Remove a Selection if needed. Spreads stay hidden when this week is Straight Up.")
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
                    Button(week.status == .locked ? "Reopen Pickems" : rollingPickDeadlineButtonTitle(week)) {
                    showPickDeadlineSheet = true
                }
                .listRowBackground(PickemsColors.cardBackground)

                if let groupId = appState.groupService.selectedGroup?.id {
                    let pickemsById = Dictionary(
                        uniqueKeysWithValues: SubmissionRoster.rows(
                            members: appState.groupService.members,
                            submissions: appState.pickService.submissions,
                            slateSize: appState.pickService.slateGames.count
                        ).map { ($0.id, $0) }
                    )
                    ForEach(appState.groupService.members) { member in
                        let row = pickemsById[member.id]
                        NavigationLink {
                            CommissionerManagePicksSheet(
                                member: member,
                                week: week,
                                groupId: groupId,
                                slateGames: appState.pickService.slateGames
                            )
                        } label: {
                            memberProgressLabel(
                                name: member.displayName,
                                made: row?.made ?? 0,
                                total: row?.total ?? appState.pickService.slateGames.count,
                                status: row?.status ?? .notStarted,
                                unitName: "Pickems"
                            )
                        }
                        .accessibilityLabel(
                            "\(member.displayName), \(row?.made ?? 0) of \(row?.total ?? appState.pickService.slateGames.count) Pickems, \(row?.status.label ?? SubmissionRosterStatus.notStarted.label). Manage Pickems."
                        )
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                }
            } header: {
                Text("Pickems Admin")
            } footer: {
                Text(week.isRollingLock
                    ? "Tap a member to force or clear their Pickems. Lock remaining freezes games that have not kicked off yet."
                    : "Tap a member to force or clear their Pickems. Counts are Pickems made versus the slate. This never removes Selections.")
            }
        }
    }

    @ViewBuilder
    private var tiesSection: some View {
        if ScoringEngine.canShowCommissionerTieBreak(
            week: week,
            games: appState.pickService.slateGames,
            tieBreaker: appState.groupService.selectedGroup?.rules.tieBreaker ?? .headToHead
        ) {
            let groups = ScoringEngine.unresolvedWeeklyTieGroups(
                from: appState.rankedStandings(weekly: true)
            )
            if !groups.isEmpty {
                Section {
                    ForEach(groups, id: \.tieGroupId) { group in
                        Button {
                            rankDraft = TieRankDraft(entries: group)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tieGroupTitle(group))
                                        .foregroundStyle(PickemsColors.textPrimary)
                                    Text(LeagueWeekRecapGenerator.joinNames(group.map(\.displayName)))
                                        .font(.caption)
                                        .foregroundStyle(PickemsColors.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 8)
                                Text("Rank")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(tieGroupTitle(group)), \(LeagueWeekRecapGenerator.joinNames(group.map(\.displayName))). Rank."
                        )
                        .accessibilityHint("Opens a list. Drag to set This Week order, then save.")
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                } header: {
                    HStack {
                        Text("Resolve Ties")
                        Spacer()
                        HelpInfoButton(topic: PickemsHelp.tieBreaker, size: .caption)
                    }
                } footer: {
                    Text("Ranks this week only. Head-to-head leagues break ties automatically.")
                }
            }
        }
    }

    private var selectionsPerMember: Int {
        let weekValue = week?.selectionsPerMember ?? 0
        if weekValue > 0 { return weekValue }
        return max(appState.groupService.selectedGroup?.rules.selectionsPerMember ?? 1, 1)
    }

    private func memberProgressLabel(
        name: String,
        made: Int,
        total: Int,
        status: SubmissionRosterStatus,
        unitName: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .foregroundStyle(PickemsColors.textPrimary)
            Spacer(minLength: 8)
            CountStatusMeter(made: made, total: total, status: status, unitName: unitName)
        }
        .accessibilityElement(children: .ignore)
    }
}

private extension [StandingEntry] {
    var tieGroupId: String {
        map(\.id).sorted().joined(separator: "|")
    }
}

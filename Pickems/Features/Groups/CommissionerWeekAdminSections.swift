import SwiftUI

/// Weekly commissioner tools. These used to live on Selections / Pickems / Leagues.
struct CommissionerWeekAdminSections: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    let present: (CommissionerSheet) -> Void
    @Binding var showReopenSelectionsConfirm: Bool

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
                    selectionDeadlineRow(week)

                    let target = appState.groupService.selectedGroup?.rules.expectedSlateSize(
                        memberCount: max(appState.groupService.selectedGroup?.memberCount ?? 1, 1)
                    ) ?? max(week.slateSize, 1)
                    if week.isSelectionDeadlinePassed {
                        if uniqueGames < target {
                            Button("Fill Remaining Games") {
                                appState.picksViewModel.selectionBrowseIntent = .own
                                present(.adminGameBrowse)
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
                } else if !week.skipsSelection {
                    closedSelectionDeadlineLabel(week)
                    if WeekTransition.canReopenSelections(week) {
                        Button("Reopen Selections") {
                            showReopenSelectionsConfirm = true
                        }
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                }

                weekManageRows(week)
            } else if displayedWeeks.isEmpty {
                Text("No active week.")
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("This Week")
        } footer: {
            Text("Deadlines, slate, Pickems, and ties for the week you pick. Switching here also switches Selections and Pickems.")
        }
    }

    private func selectAdminWeek(_ selected: WeekSummary) {
        guard selected.id != week?.id else { return }
        PickemsHaptics.selection()
        appState.selectObservedWeek(selected)
    }

    // MARK: - Selections / Slate rows

    private var canManageSelections: Bool {
        guard let week, appState.groupService.selectedGroup?.id != nil else { return false }
        return WeekTransition.commissionerCanManageSelections(week) && week.selectionMode == .member
    }

    private func canShowSlate(_ week: WeekSummary) -> Bool {
        !appState.pickService.displaySlateGames.isEmpty
            && (WeekTransition.isSlateEditable(week) || week.status == .selection)
    }

    @ViewBuilder
    private func weekManageRows(_ week: WeekSummary) -> some View {
        if canManageSelections {
            CommissionerAdminRow(
                title: "Selections",
                systemImage: "checklist",
                summary: CommissionerAdminSummary.selections(
                    memberIds: appState.groupService.members.map(\.id),
                    nominations: appState.pickService.nominations,
                    perMember: selectionsPerMember
                ),
                hint: "Opens each member's Selections to change them."
            ) {
                present(.selections)
            }
        }
        if canShowSlate(week) {
            CommissionerAdminRow(
                title: "Slate",
                systemImage: "list.bullet.rectangle",
                summary: CommissionerAdminSummary.slate(gameCount: appState.pickService.displaySlateGames.count),
                hint: "Opens the slate to edit spreads or remove a Selection."
            ) {
                present(.slate)
            }
        }
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

    /// Rolling weeks only. Non-rolling weeks use `pickemsDeadlineRow`.
    private func rollingPickDeadlineButtonTitle(_ week: WeekSummary) -> String {
        if WeekTransition.arePicksFullyLocked(week) {
            return "Lock remaining / Reopen"
        }
        return "Lock remaining games"
    }

    @ViewBuilder
    private func selectionDeadlineRow(_ week: WeekSummary) -> some View {
        switch SelectionDeadlineDisplayResolver.resolve(week: week) {
        case .open:
            if let summary = CommissionerAdminSummary.selectionDeadlineSummary(week: week) {
                selectionDeadlineEditor(summary: summary, systemImage: "clock")
            }
        case .locked:
            if let summary = CommissionerAdminSummary.selectionDeadlineSummary(week: week) {
                selectionDeadlineEditor(summary: summary, systemImage: "lock")
            }
        case .needsDeadline:
            if promptsToSetSelectionDeadline(week) {
                setSelectionDeadlineButton
            }
        case nil:
            EmptyView()
        }
    }

    private func selectionDeadlineEditor(summary: String, systemImage: String) -> some View {
        CommissionerAdminRow(
            title: "Selection Deadline",
            systemImage: systemImage,
            summary: summary,
            hint: "Opens the Selection deadline editor."
        ) {
            present(.selectionDeadline)
        }
    }

    @ViewBuilder
    private func closedSelectionDeadlineLabel(_ week: WeekSummary) -> some View {
        if case .locked = SelectionDeadlineDisplayResolver.resolve(week: week),
           let summary = CommissionerAdminSummary.selectionDeadlineSummary(week: week) {
            LabeledContent("Selection Deadline", value: summary)
                .listRowBackground(PickemsColors.cardBackground)
        }
    }

    private func promptsToSetSelectionDeadline(_ week: WeekSummary) -> Bool {
        WorkspaceDeadlineDisplay.commissionerPrompt(
            kind: .selections,
            week: week,
            isCommissioner: true
        ) == .selections
    }

    private var setSelectionDeadlineButton: some View {
        Button("Set Selection Deadline") {
            present(.selectionDeadline)
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    @ViewBuilder
    private func pickemsDeadlineRow(_ week: WeekSummary) -> some View {
        if week.status == .locked {
            reopenPickemsButton
        } else if week.isRollingLock {
            rollingPickemsDeadlineButton(week)
        } else if let summary = pickemsDeadlineSummary(week) {
            pickemsDeadlineAdminRow(summary)
        } else {
            setPickemsDeadlineButton
        }
    }

    private func pickemsDeadlineSummary(_ week: WeekSummary) -> String? {
        let locked = WeekTransition.arePicksFullyLocked(week)
        return CommissionerAdminSummary.deadlineValue(week.pickDeadline, locked: locked)
    }

    private func pickemsDeadlineAdminRow(_ summary: String) -> some View {
        CommissionerAdminRow(
            title: "Pickems Deadline",
            systemImage: "lock",
            summary: summary,
            hint: "Opens the Pickems deadline editor to change, extend, or unlock it."
        ) {
            present(.pickDeadline)
        }
    }

    private var reopenPickemsButton: some View {
        Button("Reopen Pickems") {
            present(.pickDeadline)
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    private func rollingPickemsDeadlineButton(_ week: WeekSummary) -> some View {
        Button(rollingPickDeadlineButtonTitle(week)) {
            present(.pickDeadline)
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    private var setPickemsDeadlineButton: some View {
        Button("Set Pickems Deadline") {
            present(.pickDeadline)
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    @ViewBuilder
    private var pickemsAdminSection: some View {
        if let week, WeekTransition.arePickemsOpen(week) {
            Section {
                pickemsDeadlineRow(week)

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
                            CommissionerMemberProgressRow(
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
                            present(.rankTies(TieRankDraft(entries: group)))
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
}

private extension [StandingEntry] {
    var tieGroupId: String {
        map(\.id).sorted().joined(separator: "|")
    }
}

import SwiftUI

/// Weekly commissioner tools. These used to live on Selections / Pickems / Leagues.
struct CommissionerWeekAdminSections: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    /// League this Settings screen was opened on. Live week, slate, and members
    /// are read only while their listeners are still on this id.
    let group: PickemGroup
    let present: (CommissionerSheetRequest) -> Void
    let requestReopenSelections: (WeekSummary) -> Void
    /// Pickems admin push. The route lives on Settings, not on this row, so a
    /// member-list snapshot cannot pop the screen.
    var managePicks: (GroupMember, WeekSummary, [SlateGame]) -> Void = { _, _, _ in }

    private var picksVM: PicksViewModel { appState.picksViewModel }
    private var groupId: String { group.id }
    private var week: WeekSummary? {
        guard appState.groupService.currentWeekGroupId == groupId else { return nil }
        return appState.groupService.currentWeek
    }
    private var pinnedMembers: [GroupMember] {
        guard appState.groupService.membersGroupId == groupId else { return [] }
        return appState.groupService.members
    }
    private var pinnedSlate: [SlateGame] {
        CommissionerPinnedLeague.slate(
            pinnedGroupId: groupId,
            observingGroupId: appState.pickService.observingGroupId,
            live: appState.pickService.slateGames,
            captured: []
        )
    }
    private var pinnedNominations: [Nomination] {
        guard appState.pickService.observingGroupId == groupId else { return [] }
        return appState.pickService.nominations
    }
    private var uniqueGames: Int {
        Set(pinnedNominations.map(\.espnEventId) + pinnedSlate.map(\.espnEventId)).count
    }

    var body: some View {
        weekStatusSection
        pickemsAdminSection
        tiesSection
    }

    private var displayedWeeks: [WeekSummary] {
        guard appState.groupService.availableWeeksBelong(to: groupId) else { return [] }
        return appState.groupService.availableWeeks
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

                if !week.skipsSelection {
                    selectionDeadlineRow(week)
                }
                if week.status == .selection, !week.skipsSelection {
                    let target = group.rules.expectedSlateSize(
                        memberCount: max(group.memberCount, 1)
                    )
                    if week.isSelectionDeadlinePassed {
                        if uniqueGames < target {
                            Button("Fill Remaining Games") {
                                appState.picksViewModel.selectionBrowseIntent = .own
                                present(.adminGameBrowse(week))
                            }
                            .listRowBackground(PickemsColors.cardBackground)
                        }
                        Button("Open With \(uniqueGames) Game\(uniqueGames == 1 ? "" : "s")") {
                            picksVM.openWeekWithCurrentSlate(
                                groupId: groupId,
                                week: week,
                                rules: group.rules,
                                appState: appState
                            )
                        }
                        .disabled(uniqueGames == 0)
                        .listRowBackground(PickemsColors.cardBackground)
                    } else {
                        Button("Open Week Early") {
                            picksVM.openWeekWithCurrentSlate(
                                groupId: groupId,
                                week: week,
                                rules: group.rules,
                                appState: appState
                            )
                        }
                        .disabled(uniqueGames == 0)
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                } else if !week.skipsSelection, WeekTransition.canReopenSelections(week) {
                    Button("Reopen Selections") {
                        requestReopenSelections(week)
                    }
                    .listRowBackground(PickemsColors.cardBackground)
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
        guard let week else { return false }
        return WeekTransition.commissionerCanManageSelections(week) && week.selectionMode == .member
    }

    private func canShowSlate(_ week: WeekSummary) -> Bool {
        !pinnedDisplaySlate.isEmpty
            && (WeekTransition.isSlateEditable(week) || week.status == .selection)
    }

    private var pinnedDisplaySlate: [SlateGame] {
        guard appState.pickService.observingGroupId == groupId else { return [] }
        return appState.pickService.displaySlateGames
    }

    @ViewBuilder
    private func weekManageRows(_ week: WeekSummary) -> some View {
        if canManageSelections {
            CommissionerAdminRow(
                title: "Selections",
                systemImage: "checklist",
                summary: CommissionerAdminSummary.selections(
                    memberIds: pinnedMembers.map(\.id),
                    nominations: pinnedNominations,
                    perMember: selectionsPerMember
                ),
                hint: "Opens each member's Selections to change them."
            ) {
                present(.selections(week))
            }
        }
        if canShowSlate(week) {
            CommissionerAdminRow(
                title: "Slate",
                systemImage: "list.bullet.rectangle",
                summary: CommissionerAdminSummary.slate(gameCount: pinnedDisplaySlate.count),
                hint: "Opens the slate to edit spreads or remove a Selection."
            ) {
                present(.slate(week))
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
        switch CommissionerSelectionDeadlineRow.resolve(week: week) {
        case .editor(let summary):
            let counting = SelectionDeadlineDisplayResolver.resolve(week: week)?.isCountingDown == true
            selectionDeadlineEditor(
                summary: summary,
                systemImage: counting ? "clock" : "lock",
                week: week
            )
        case .setPrompt:
            setSelectionDeadlineButton(week)
        case .hidden:
            EmptyView()
        }
    }

    private func selectionDeadlineEditor(summary: String, systemImage: String, week: WeekSummary) -> some View {
        CommissionerAdminRow(
            title: "Selection Deadline",
            systemImage: systemImage,
            summary: summary,
            hint: "Opens the Selection deadline editor."
        ) {
            present(.selectionDeadline(week))
        }
    }

    private func setSelectionDeadlineButton(_ week: WeekSummary) -> some View {
        Button("Set Selection Deadline") {
            present(.selectionDeadline(week))
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    @ViewBuilder
    private func pickemsDeadlineRow(_ week: WeekSummary) -> some View {
        if week.status == .locked {
            reopenPickemsButton(week)
        } else if week.isRollingLock {
            rollingPickemsDeadlineButton(week)
        } else if let summary = pickemsDeadlineSummary(week) {
            pickemsDeadlineAdminRow(summary, week: week)
        } else {
            setPickemsDeadlineButton(week)
        }
    }

    private func pickemsDeadlineSummary(_ week: WeekSummary) -> String? {
        let locked = WeekTransition.arePicksFullyLocked(week)
        return CommissionerAdminSummary.deadlineValue(week.pickDeadline, locked: locked)
    }

    private func pickemsDeadlineAdminRow(_ summary: String, week: WeekSummary) -> some View {
        CommissionerAdminRow(
            title: "Pickems Deadline",
            systemImage: "lock",
            summary: summary,
            hint: "Opens the Pickems deadline editor to change, extend, or unlock it."
        ) {
            present(.pickDeadline(week))
        }
    }

    private func reopenPickemsButton(_ week: WeekSummary) -> some View {
        Button("Reopen Pickems") {
            present(.pickDeadline(week))
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    private func rollingPickemsDeadlineButton(_ week: WeekSummary) -> some View {
        Button(rollingPickDeadlineButtonTitle(week)) {
            present(.pickDeadline(week))
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    private func setPickemsDeadlineButton(_ week: WeekSummary) -> some View {
        Button("Set Pickems Deadline") {
            present(.pickDeadline(week))
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    @ViewBuilder
    private var pickemsAdminSection: some View {
        if let week, WeekTransition.arePickemsOpen(week) {
            Section {
                pickemsDeadlineRow(week)

                let submissions = appState.pickService.observingGroupId == groupId
                    ? appState.pickService.submissions
                    : []
                let pickemsById = Dictionary(
                    uniqueKeysWithValues: SubmissionRoster.rows(
                        members: pinnedMembers,
                        submissions: submissions,
                        slateSize: pinnedSlate.count
                    ).map { ($0.id, $0) }
                )
                ForEach(pinnedMembers) { member in
                    let row = pickemsById[member.id]
                    Button {
                        managePicks(member, week, pinnedSlate)
                    } label: {
                        CommissionerMemberProgressRow(
                            name: member.displayName,
                            made: row?.made ?? 0,
                            total: row?.total ?? pinnedSlate.count,
                            status: row?.status ?? .notStarted,
                            unitName: "Pickems"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(member.displayName), \(row?.made ?? 0) of \(row?.total ?? pinnedSlate.count) Pickems, \(row?.status.label ?? SubmissionRosterStatus.notStarted.label). Manage Pickems."
                    )
                    .listRowBackground(PickemsColors.cardBackground)
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
        if let week, ScoringEngine.canShowCommissionerTieBreak(
            week: week,
            games: pinnedSlate,
            tieBreaker: group.rules.tieBreaker
        ) {
            let groups = ScoringEngine.unresolvedWeeklyTieGroups(
                from: appState.rankedStandings(weekly: true)
            )
            if !groups.isEmpty {
                Section {
                    ForEach(groups, id: \.tieGroupId) { group in
                        Button {
                            present(.rankTies(TieRankDraft(entries: group), week))
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
        return max(group.rules.selectionsPerMember, 1)
    }
}

private extension [StandingEntry] {
    var tieGroupId: String {
        map(\.id).sorted().joined(separator: "|")
    }
}

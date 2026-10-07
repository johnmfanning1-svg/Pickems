import SwiftUI

// Condensed Commissioner Settings rows (Selections, Slate, Members) and the sheets
// they open. Each sheet carries the full list and every action the old inline
// section had.

/// One condensed row: title on the left, summary and chevron on the right.
struct CommissionerAdminRow: View {
    let title: String
    let systemImage: String
    let summary: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(PickemsColors.textPrimary)
                Spacer(minLength: 8)
                Text(summary)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(PickemsColors.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .listRowBackground(PickemsColors.cardBackground)
    }
}

/// Member name with a made/total meter. Shared by Selections and Pickems admin.
struct CommissionerMemberProgressRow: View {
    let name: String
    let made: Int
    let total: Int
    let status: SubmissionRosterStatus
    let unitName: String

    var body: some View {
        HStack(spacing: 12) {
            Text(name)
                .foregroundStyle(PickemsColors.textPrimary)
            Spacer(minLength: 8)
            CountStatusMeter(made: made, total: total, status: status, unitName: unitName)
        }
        .accessibilityElement(children: .ignore)
    }
}

/// Sheet chrome shared by the admin sheets: navigation, Done, themed background.
private struct CommissionerAdminSheetChrome<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            Form {
                content()
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Selections

/// Was the inline "Selections Admin" section.
struct CommissionerSelectionsAdminSheet: View {
    @Environment(AppState.self) private var appState

    private var week: WeekSummary? { appState.groupService.currentWeek }

    private var selectionsPerMember: Int {
        let weekValue: Int = week?.selectionsPerMember ?? 0
        if weekValue > 0 { return weekValue }
        return max(appState.groupService.selectedGroup?.rules.selectionsPerMember ?? 1, 1)
    }

    var body: some View {
        CommissionerAdminSheetChrome(title: "Selections") {
            if let week, let groupId = appState.groupService.selectedGroup?.id {
                Section {
                    ForEach(appState.groupService.members) { (member: GroupMember) in
                        memberLink(member, week: week, groupId: groupId)
                    }
                } header: {
                    Text(week.displayLabel)
                } footer: {
                    Text("Tap a member to change their Selections. Counts are games submitted versus the weekly requirement.")
                }
            } else {
                Text("No active week.")
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        }
    }

    private func memberLink(_ member: GroupMember, week: WeekSummary, groupId: String) -> some View {
        let progress = SubmissionRoster.selectionProgress(
            nominations: appState.pickService.nominations,
            memberId: member.id,
            perMember: selectionsPerMember
        )
        return NavigationLink {
            CommissionerManageSelectionsSheet(member: member, week: week, groupId: groupId)
        } label: {
            CommissionerMemberProgressRow(
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
}

// MARK: - Slate

/// Was the inline "This Week's Slate" section, plus the spread editor sheet.
struct CommissionerSlateSheet: View {
    @Environment(AppState.self) private var appState
    @State private var spreadEditGame: SlateGame?

    private var picksVM: PicksViewModel { appState.picksViewModel }
    private var week: WeekSummary? { appState.groupService.currentWeek }
    private var showsSpreads: Bool { appState.selectedPickMode.showsSpreads }

    var body: some View {
        CommissionerAdminSheetChrome(title: "Slate") {
            slateSection
        }
        .sheet(item: $spreadEditGame) { (game: SlateGame) in
            spreadEditorSheet(for: game)
        }
    }

    @ViewBuilder
    private var slateSection: some View {
        let games: [SlateGame] = appState.pickService.displaySlateGames
        if let week, !games.isEmpty {
            Section {
                ForEach(games) { (game: SlateGame) in
                    gameRow(game, week: week)
                }
            } header: {
                Text(week.displayLabel)
            } footer: {
                Text(showsSpreads
                    ? "Edit lines or remove a Selection. Members remake their own Selections on the Selections tab before the deadline."
                    : "Remove a Selection if needed. Spreads stay hidden when this week is Straight Up.")
            }
        } else {
            Text("No games on the slate yet.")
                .foregroundStyle(PickemsColors.textSecondary)
                .listRowBackground(PickemsColors.cardBackground)
        }
    }

    private func gameRow(_ game: SlateGame, week: WeekSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(matchupLabel(game))
                .foregroundStyle(PickemsColors.textPrimary)
            if showsSpreads {
                LockedSpreadLabel(
                    lockedText: game.favoriteSpreadDisplay,
                    liveText: picksVM.livePickCards[game.espnEventId]?.liveSpreadLabel
                )
            }
            HStack {
                if showsSpreads {
                    Button("Edit Spread") { spreadEditGame = game }
                }
                if !week.skipsSelection {
                    Spacer()
                    Button("Remove Selection", role: .destructive) {
                        removeSlateItem(game, week: week)
                    }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    private func matchupLabel(_ game: SlateGame) -> String {
        TeamDisplay.matchupLabel(
            awayAbbreviation: game.awayTeamName,
            awayRank: picksVM.teamRanks.rank(for: game.awayTeamId),
            homeAbbreviation: game.homeTeamName,
            homeRank: picksVM.teamRanks.rank(for: game.homeTeamId),
            separator: game.matchupSeparator
        )
    }

    private func removeSlateItem(_ game: SlateGame, week: WeekSummary) {
        if let live = appState.pickService.slateGames.first(where: {
            $0.id == game.id || $0.espnEventId == game.espnEventId
        }) {
            picksVM.removeCommissionerGame(live, week: week, appState: appState)
        } else if let nom = appState.pickService.nominations.first(where: { $0.espnEventId == game.espnEventId }) {
            let rules: GroupRules = appState.groupService.selectedGroup?.rules ?? .default
            picksVM.removeNomination(nom, rules: rules, appState: appState)
        }
    }

    private func spreadEditorSheet(for game: SlateGame) -> some View {
        SpreadEditorSheet(game: game) { spread, spreadTeamId in
            appState.picksViewModel.updateSpread(
                game,
                spread: spread,
                spreadTeamId: spreadTeamId,
                appState: appState
            )
        }
        .pickemsEnvironment(appState)
    }
}

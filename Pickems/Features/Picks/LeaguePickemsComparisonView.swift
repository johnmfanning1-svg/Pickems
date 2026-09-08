import SwiftUI

/// Head-to-head league chart: Game | You | selected member.
struct LeaguePickemsComparisonView: View {
    let opponent: StandingEntry

    @Environment(AppState.self) private var appState

    private var week: WeekSummary? {
        appState.groupService.currentWeek
    }

    private var games: [SlateGame] {
        appState.pickService.slateGames.sortedByKickoff
    }

    private var currentUserId: String? {
        appState.currentUserId
    }

    private var members: [GroupMember] {
        appState.groupService.members
    }

    private var picksByUserId: [String: UserPick] {
        appState.pickService.boardPicksByUserId(
            members: members,
            ownUserId: currentUserId
        )
    }

    private var hiddenGameIds: Set<String> {
        guard let week, week.isRollingLock, !WeekTransition.pickemsAreFullyPublic(week) else {
            return []
        }
        return Set(
            games
                .filter { !WeekTransition.isGameLocked($0, week: week) }
                .map(\.id)
        )
    }

    private var yourStanding: StandingEntry? {
        appState.rankedStandings(weekly: true).first { $0.id == currentUserId }
    }

    private var opponentMember: GroupMember {
        if let member = members.first(where: { $0.id == opponent.id }) {
            return member
        }
        return Self.member(from: opponent)
    }

    private var youMember: GroupMember? {
        if let currentUserId, let member = members.first(where: { $0.id == currentUserId }) {
            return member
        }
        if let standing = yourStanding {
            return Self.member(from: standing)
        }
        return nil
    }

    private var comparisonMembers: [GroupMember] {
        var result: [GroupMember] = []
        if let youMember {
            result.append(youMember)
        }
        result.append(opponentMember)
        return result
    }

    private var opponentShortName: String {
        let parts = opponent.displayName.split(separator: " ")
        if let first = parts.first { return String(first) }
        return opponent.displayName
    }

    private var samePickSummary: (same: Int, visible: Int) {
        LeaguePickemsComparisonStats.samePickCount(
            games: games,
            youPicks: currentUserId.flatMap { picksByUserId[$0]?.picks },
            themPicks: picksByUserId[opponent.id]?.picks,
            hiddenGameIds: hiddenGameIds
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                comparisonHeader
                if games.isEmpty {
                    EmptyStateView(
                        icon: "american.football.fill",
                        title: "No slate games",
                        message: "This week locked without games on the slate.",
                        help: PickemsHelp.leaguePickems
                    )
                } else {
                    LeaguePickemsBoard(
                        members: comparisonMembers,
                        games: games,
                        picksByUserId: picksByUserId,
                        liveCards: appState.picksViewModel.livePickCards,
                        teamRanks: appState.picksViewModel.teamRanks,
                        currentUserId: currentUserId,
                        hiddenGameIds: hiddenGameIds
                    )
                }
            }
            .padding()
        }
        .pickemsScreenBackground()
        .navigationTitle("You vs \(opponentShortName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            HelpToolbarItem(topic: PickemsHelp.leaguePickems)
        }
        .task(id: "\(appState.groupService.selectedGroup?.id ?? "")-\(week?.id ?? "")") {
            await appState.picksViewModel.ensureTeamRanks(appState: appState)
            if let week {
                appState.picksViewModel.startLiveRefresh(week: week, appState: appState)
            }
        }
    }

    private var comparisonHeader: some View {
        let same = samePickSummary
        return PickemsCard {
            HStack(alignment: .top, spacing: 12) {
                recordBlock(
                    title: "You",
                    value: recordText(yourStanding)
                )
                recordBlock(
                    title: opponentShortName,
                    value: "\(opponent.weeklyWins)-\(opponent.weeklyLosses)"
                )
                recordBlock(
                    title: "Same pick",
                    value: "\(same.same) of \(same.visible)"
                )
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "You \(recordText(yourStanding)) this week. \(opponent.displayName) \(opponent.weeklyWins)-\(opponent.weeklyLosses) this week. Same pick on \(same.same) of \(same.visible) games."
            )
        }
    }

    private func recordBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(PickemsColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordText(_ entry: StandingEntry?) -> String {
        guard let entry else { return "0-0" }
        return "\(entry.weeklyWins)-\(entry.weeklyLosses)"
    }

    private static func member(from standing: StandingEntry) -> GroupMember {
        GroupMember(
            id: standing.id,
            displayName: standing.displayName,
            avatarColorHex: standing.avatarColorHex,
            role: .member,
            joinedAt: standing.joinedAt ?? Date(timeIntervalSince1970: 0),
            seasonWins: standing.seasonWins,
            seasonLosses: standing.seasonLosses,
            avatarImageURL: standing.avatarImageURL
        )
    }
}

nonisolated enum LeaguePickemsComparisonStats {
    static func samePickCount(
        games: [SlateGame],
        youPicks: [String: String]?,
        themPicks: [String: String]?,
        hiddenGameIds: Set<String>
    ) -> (same: Int, visible: Int) {
        let visible = games.filter { !hiddenGameIds.contains($0.id) }
        let you = youPicks ?? [:]
        let them = themPicks ?? [:]
        let same = visible.filter { game in
            guard let yours = you[game.id], !yours.isEmpty,
                  let theirs = them[game.id], !theirs.isEmpty else {
                return false
            }
            return yours == theirs
        }.count
        return (same, visible.count)
    }
}

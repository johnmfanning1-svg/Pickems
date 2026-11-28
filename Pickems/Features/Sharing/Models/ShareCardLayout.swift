import CoreGraphics
import Foundation

enum ShareCardLayout {
    static let leaderboardRowLimit = 8
    static let ledgerMemberColumnLimit = 6
    static let chartOtherMemberLimit = 5
    static let renderWidth: CGFloat = 1080
    static let minRenderHeight: CGFloat = 1080
    static let maxRenderHeight: CGFloat = 1920
    static let maxChartGameRows = 14

    struct LeaderboardLayout: Equatable, Sendable {
        let rows: [ShareLeaderboardRow]
        let omittedCount: Int
    }

    struct SeasonLedgerLayout: Equatable, Sendable {
        let columns: [ShareLedgerMemberColumn]
        let weeks: [ShareLedgerWeekRow]
        let seasonTotals: [ShareLedgerWLPair]
        let gamesBack: [String]
        let omittedMemberCount: Int
    }

    struct PickemsChartLayout: Equatable, Sendable {
        let columns: [ShareChartMemberColumn]
        let games: [ShareChartGameRow]
        let omittedMemberCount: Int
        let omittedGameCount: Int
    }

    static func leaderboardPeriodLabel(scope: LeaderboardScope.Scope) -> String {
        switch scope {
        case .thisWeek: return "This Week"
        case .season: return "Season"
        case .bowl: return CFBBowlSeason.userFacingBowlWeekName
        }
    }

    static func leaderboard(
        entries: [StandingEntry],
        scope: LeaderboardScope.Scope,
        viewerId: String?,
        leaderWins: Int?
    ) -> LeaderboardLayout {
        let showWeekly = scope == .thisWeek
        let showBowl = scope == .bowl

        func row(for entry: StandingEntry) -> ShareLeaderboardRow {
            let wins = showWeekly ? entry.weeklyWins : entry.seasonWins
            let losses = showWeekly ? entry.weeklyLosses : entry.seasonLosses
            let caption = StandingsGap.leaderboardCaption(
                rank: entry.rank,
                wins: wins,
                losses: losses,
                leaderWins: leaderWins
            )
            return ShareLeaderboardRow(
                rank: entry.rank,
                displayName: entry.displayName,
                avatarColorHex: entry.avatarColorHex,
                wins: wins,
                losses: losses,
                caption: caption,
                isViewer: entry.id == viewerId
            )
        }

        var selectedEntries = Array(entries.prefix(leaderboardRowLimit))
        if let viewerId,
           !selectedEntries.contains(where: { $0.id == viewerId }),
           let viewerEntry = entries.first(where: { $0.id == viewerId }) {
            if selectedEntries.count >= leaderboardRowLimit {
                selectedEntries.removeLast()
            }
            selectedEntries.append(viewerEntry)
        }

        let rows = selectedEntries.map(row)
        let omittedCount = entries.count <= selectedEntries.count
            ? 0
            : entries.count - selectedEntries.count

        return LeaderboardLayout(rows: rows, omittedCount: omittedCount)
    }

    static func seasonLedger(
        data: SeasonLedgerSeasonData,
        members: [GroupMember],
        currentUserId: String?
    ) -> SeasonLedgerLayout {
        let ordered = SeasonLedgerMembers.ordered(members, currentUserId: currentUserId)
        let trimmed = trimmedLedgerMembers(ordered, data: data, currentUserId: currentUserId)
        let omittedMemberCount = max(0, ordered.count - trimmed.count)

        let columns = trimmed.map {
            ShareLedgerMemberColumn(
                shortName: SeasonLedgerMembers.shortName($0, currentUserId: currentUserId),
                isViewer: $0.id == currentUserId
            )
        }

        let weeks: [ShareLedgerWeekRow] = data.weeks.map { board in
            let records = trimmed.map { member in
                let record = board.recordsByMemberId[member.id] ?? .zero
                return ShareLedgerWLPair(wins: record.wins, losses: record.losses)
            }
            return ShareLedgerWeekRow(
                title: SeasonLedgerWeekTitle.rowTitle(for: board.week),
                records: records
            )
        }

        let seasonTotals = trimmed.map { member in
            let season = data.seasonRecord(for: member.id)
            return ShareLedgerWLPair(wins: season.wins, losses: season.losses)
        }

        let leaderWins = SeasonLedgerGamesBack.leaderWins(memberSeasonWins: data.seasonWinsByMemberId())
        let gamesBack = trimmed.map { member in
            let wins = data.seasonRecord(for: member.id).wins
            return SeasonLedgerGamesBack.caption(memberWins: wins, leaderWins: leaderWins)
        }

        return SeasonLedgerLayout(
            columns: columns,
            weeks: weeks,
            seasonTotals: seasonTotals,
            gamesBack: gamesBack,
            omittedMemberCount: omittedMemberCount
        )
    }

  /// Viewer first, then members with the most season wins, capped at `ledgerMemberColumnLimit`.
    private static func trimmedLedgerMembers(
        _ members: [GroupMember],
        data: SeasonLedgerSeasonData,
        currentUserId: String?
    ) -> [GroupMember] {
        guard members.count > ledgerMemberColumnLimit else { return members }
        let viewer = members.first { $0.id == currentUserId }
        let others = members.filter { $0.id != currentUserId }
        let ranked = others.sorted { lhs, rhs in
            let left = data.seasonRecord(for: lhs.id).wins
            let right = data.seasonRecord(for: rhs.id).wins
            if left != right { return left > right }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        var result: [GroupMember] = []
        if let viewer { result.append(viewer) }
        let slots = ledgerMemberColumnLimit - result.count
        result.append(contentsOf: ranked.prefix(slots))
        return result
    }

    static func pickemsChart(
        members: [GroupMember],
        games: [SlateGame],
        picksByUserId: [String: UserPick],
        hiddenGameIds: Set<String>,
        pickMode: PickMode,
        currentUserId: String?,
        liveCards: [String: ESPNLiveGameCard]
    ) -> PickemsChartLayout {
        let ordered = SeasonLedgerMembers.ordered(members, currentUserId: currentUserId)
        let trimmed = trimmedChartMembers(ordered, picksByUserId: picksByUserId, games: games, currentUserId: currentUserId)
        let omittedMemberCount = max(0, ordered.count - trimmed.count)

        let columns = trimmed.map {
            ShareChartMemberColumn(
                shortName: SeasonLedgerMembers.shortName($0, currentUserId: currentUserId),
                isViewer: $0.id == currentUserId
            )
        }

        let sortedGames = games.sortedByKickoff
        let visibleGames = Array(sortedGames.prefix(maxChartGameRows))
        let omittedGameCount = max(0, sortedGames.count - visibleGames.count)

        let gameRows: [ShareChartGameRow] = visibleGames.map { game in
            let live = liveCards[game.espnEventId]
            let cells = trimmed.map { member in
                chartCell(
                    game: game,
                    member: member,
                    picksByUserId: picksByUserId,
                    hiddenGameIds: hiddenGameIds,
                    pickMode: pickMode,
                    currentUserId: currentUserId,
                    live: live
                )
            }
            let scoreLine: String? = {
                let status = live?.status ?? game.status
                guard status == .final else { return nil }
                return SeasonLedgerGameCopy.scoreLine(game)
            }()
            return ShareChartGameRow(
                matchup: SeasonLedgerGameCopy.matchup(game, showsSpreads: pickMode.showsSpreads),
                scoreLine: scoreLine,
                cells: cells
            )
        }

        return PickemsChartLayout(
            columns: columns,
            games: gameRows,
            omittedMemberCount: omittedMemberCount,
            omittedGameCount: omittedGameCount
        )
    }

    private static func trimmedChartMembers(
        _ members: [GroupMember],
        picksByUserId: [String: UserPick],
        games: [SlateGame],
        currentUserId: String?
    ) -> [GroupMember] {
        let limit = chartOtherMemberLimit + (currentUserId == nil ? 0 : 1)
        guard members.count > limit else { return members }

        let viewer = members.first { $0.id == currentUserId }
        let others = members.filter { $0.id != currentUserId }

        func pickCount(for member: GroupMember) -> Int {
            guard let pick = picksByUserId[member.id] else { return 0 }
            return games.reduce(0) { partial, game in
                partial + (pick.picks[game.id] != nil ? 1 : 0)
            }
        }

        let ranked = others.sorted { lhs, rhs in
            let left = pickCount(for: lhs)
            let right = pickCount(for: rhs)
            if left != right { return left > right }
            return lhs.seasonWins != rhs.seasonWins
                ? lhs.seasonWins > rhs.seasonWins
                : lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        var result: [GroupMember] = []
        if let viewer { result.append(viewer) }
        result.append(contentsOf: ranked.prefix(chartOtherMemberLimit))
        return result
    }

    private static func chartCell(
        game: SlateGame,
        member: GroupMember,
        picksByUserId: [String: UserPick],
        hiddenGameIds: Set<String>,
        pickMode: PickMode,
        currentUserId: String?,
        live: ESPNLiveGameCard?
    ) -> ShareChartCell {
        guard SeasonLedgerPrivacy.mayShowPick(
            gameId: game.id,
            memberId: member.id,
            viewerId: currentUserId,
            hiddenGameIds: hiddenGameIds
        ) else {
            return ShareChartCell(kind: .locked)
        }

        let pickedId = picksByUserId[member.id]?.picks[game.id]
        guard let pickedId, !pickedId.isEmpty else {
            return ShareChartCell(kind: .empty)
        }

        let status = ScoringEngine.pickBoardStatus(
            pickedTeamId: pickedId,
            game: game,
            homeScore: live?.homeScore ?? game.homeScore,
            awayScore: live?.awayScore ?? game.awayScore,
            status: live?.status ?? game.status,
            pickMode: pickMode
        )
        let abbrev = pickAbbreviation(game: game, pickedTeamId: pickedId)
        return ShareChartCell(kind: .pick(abbrev, status))
    }

    private static func pickAbbreviation(game: SlateGame, pickedTeamId: String) -> String {
        if pickedTeamId == game.homeTeamId { return game.homeTeamAbbreviation }
        if pickedTeamId == game.awayTeamId { return game.awayTeamAbbreviation }
        return "PICK"
    }
}
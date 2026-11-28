import CoreGraphics
import Foundation

enum ShareCardLayout {
    static let leaderboardRowLimit = 8
    static let renderWidth: CGFloat = 1080
    static let chromeHorizontalPadding: CGFloat = 48
    static let minMemberColumnWidth: CGFloat = 72
    static let maxMemberColumnWidth: CGFloat = 120
    static let minGameColumnWidth: CGFloat = 164
    static let ledgerWeekColumnWidth: CGFloat = 120
    static let maxChartGameRows = 14

    /// Inner chart width inside `ShareCardChrome` (full card width minus horizontal padding).
    static var chartInnerWidth: CGFloat {
        renderWidth - chromeHorizontalPadding * 2
    }

    struct ChartColumnMetrics: Equatable, Sendable {
        let leadColumnWidth: CGFloat
        let memberColumnWidth: CGFloat
        let maxMemberColumnSlots: Int
    }

    static func tableContentWidth(
        leadWidth: CGFloat,
        memberWidth: CGFloat,
        memberCount: Int
    ) -> CGFloat {
        leadWidth + CGFloat(max(0, memberCount)) * memberWidth
    }

    static func maxMemberColumnSlots(minimumLeadWidth: CGFloat = minGameColumnWidth) -> Int {
        max(1, Int(floor((chartInnerWidth - minimumLeadWidth) / minMemberColumnWidth)))
    }

    /// Sizes lead (game/week) and member columns to span `chartInnerWidth`, expanding the lead column when the league is small.
    static func tableColumnMetrics(
        memberCount: Int,
        minimumLeadWidth: CGFloat = minGameColumnWidth
    ) -> ChartColumnMetrics {
        let count = max(1, memberCount)
        let inner = chartInnerWidth
        var memberWidth = min(
            maxMemberColumnWidth,
            max(minMemberColumnWidth, (inner - minimumLeadWidth) / CGFloat(count))
        )
        var leadWidth = inner - CGFloat(count) * memberWidth
        if leadWidth < minimumLeadWidth {
            memberWidth = (inner - minimumLeadWidth) / CGFloat(count)
            leadWidth = minimumLeadWidth
        }
        let slots = maxMemberColumnSlots(minimumLeadWidth: minimumLeadWidth)
        return ChartColumnMetrics(
            leadColumnWidth: leadWidth,
            memberColumnWidth: memberWidth,
            maxMemberColumnSlots: slots
        )
    }

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
        let memberColumnWidth: CGFloat
        let weekColumnWidth: CGFloat
    }

    struct PickemsChartLayout: Equatable, Sendable {
        let columns: [ShareChartMemberColumn]
        let games: [ShareChartGameRow]
        let stillToPlay: ShareStillToPlayStrip?
        let omittedMemberCount: Int
        let omittedGameCount: Int
        let metrics: ChartColumnMetrics
    }

    static func leaderboardPeriodLabel(scope: LeaderboardScope.Scope) -> String {
        switch scope {
        case .thisWeek: return "This Week"
        case .season: return "Season"
        case .bowl: return CFBBowlSeason.userFacingBowlWeekName
        }
    }

    static func standingsRankedMembers(_ members: [GroupMember]) -> [GroupMember] {
        members.sorted { lhs, rhs in
            if lhs.seasonWins != rhs.seasonWins { return lhs.seasonWins > rhs.seasonWins }
            if lhs.seasonLosses != rhs.seasonLosses { return lhs.seasonLosses < rhs.seasonLosses }
            return lhs.id < rhs.id
        }
    }

    /// Sharer first, then members nearest in current standings (alternate above/below sharer rank).
    static func membersForShareColumns(
        members: [GroupMember],
        currentUserId: String?,
        limit: Int
    ) -> [GroupMember] {
        guard limit > 0 else { return [] }
        let ranked = standingsRankedMembers(members)
        guard !ranked.isEmpty else { return [] }
        guard let currentUserId,
              let viewerIndex = ranked.firstIndex(where: { $0.id == currentUserId }) else {
            return Array(ranked.prefix(limit))
        }

        var selected: [GroupMember] = [ranked[viewerIndex]]
        var above = viewerIndex - 1
        var below = viewerIndex + 1
        var pickAbove = true

        while selected.count < limit {
            if pickAbove, above >= 0 {
                selected.append(ranked[above])
                above -= 1
            } else if below < ranked.count {
                selected.append(ranked[below])
                below += 1
            } else if above >= 0 {
                selected.append(ranked[above])
                above -= 1
            } else {
                break
            }
            pickAbove.toggle()
        }
        return selected
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
        let slotCap = maxMemberColumnSlots(minimumLeadWidth: ledgerWeekColumnWidth)
        let trimmed = membersForShareColumns(
            members: members,
            currentUserId: currentUserId,
            limit: slotCap
        )
        let metrics = tableColumnMetrics(
            memberCount: trimmed.count,
            minimumLeadWidth: ledgerWeekColumnWidth
        )
        let omittedMemberCount = max(0, members.count - trimmed.count)

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
            omittedMemberCount: omittedMemberCount,
            memberColumnWidth: metrics.memberColumnWidth,
            weekColumnWidth: metrics.leadColumnWidth
        )
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
        let slotCap = maxMemberColumnSlots()
        let trimmed = membersForShareColumns(
            members: members,
            currentUserId: currentUserId,
            limit: slotCap
        )
        let metrics = tableColumnMetrics(memberCount: trimmed.count)
        let omittedMemberCount = max(0, members.count - trimmed.count)

        let columns = trimmed.map {
            ShareChartMemberColumn(
                shortName: SeasonLedgerMembers.shortName($0, currentUserId: currentUserId),
                isViewer: $0.id == currentUserId
            )
        }

        let sortedGames = games.sortedByKickoff
        let (gridGames, stillToPlayGames) = sortedGames.partitioned { game in
            let status = liveCards[game.espnEventId]?.status ?? game.status
            return status != .scheduled
        }

        let visibleGridGames = Array(gridGames.prefix(maxChartGameRows))
        let omittedGameCount = max(0, gridGames.count - visibleGridGames.count)

        let gameRows: [ShareChartGameRow] = visibleGridGames.map { game in
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
            let matchup = matchupLine(
                game: game,
                live: live,
                showsSpreads: pickMode.showsSpreads
            )
            return ShareChartGameRow(matchup: matchup, cells: cells)
        }

        let stillToPlay = stillToPlayStrip(
            games: stillToPlayGames,
            picksByUserId: picksByUserId,
            hiddenGameIds: hiddenGameIds,
            currentUserId: currentUserId,
            pickMode: pickMode
        )

        return PickemsChartLayout(
            columns: columns,
            games: gameRows,
            stillToPlay: stillToPlay,
            omittedMemberCount: omittedMemberCount,
            omittedGameCount: omittedGameCount,
            metrics: metrics
        )
    }

    private static func stillToPlayStrip(
        games: [SlateGame],
        picksByUserId: [String: UserPick],
        hiddenGameIds: Set<String>,
        currentUserId: String?,
        pickMode: PickMode
    ) -> ShareStillToPlayStrip? {
        guard !games.isEmpty else { return nil }
        let viewerId = currentUserId
        let chips = games.compactMap { game -> String? in
            guard let viewerId else { return nil }
            let pickedId = picksByUserId[viewerId]?.picks[game.id]
            guard let pickedId, !pickedId.isEmpty else { return nil }
            return pickAbbreviation(game: game, pickedTeamId: pickedId)
        }
        let picksHidden = games.contains { hiddenGameIds.contains($0.id) }
        let note = picksHidden ? "Picks hidden until kickoff" : nil
        return ShareStillToPlayStrip(chips: chips, picksHiddenNote: note)
    }

    private static func matchupLine(
        game: SlateGame,
        live: ESPNLiveGameCard?,
        showsSpreads: Bool
    ) -> String {
        let base = SeasonLedgerGameCopy.matchup(game, showsSpreads: showsSpreads)
        let status = live?.status ?? game.status
        if status == .final {
            if let away = game.awayScore, let home = game.homeScore {
                return "\(base)  \(away)–\(home)"
            }
        } else if status == .inProgress {
            let away = live?.awayScore ?? game.awayScore
            let home = live?.homeScore ?? game.homeScore
            if let away, let home {
                return "\(base)  \(away)–\(home)"
            }
        }
        return base
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

private extension Array {
    func partitioned(by belongsInFirstPartition: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for element in self {
            if belongsInFirstPartition(element) {
                first.append(element)
            } else {
                second.append(element)
            }
        }
        return (first, second)
    }
}
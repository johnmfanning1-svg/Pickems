import Foundation

/// Pure league-profile facts. Views render the result and do not decide which
/// pick sheets are safe to summarize.
///
/// A sheet counts only when the week is already scored, or the week is locked
/// and that member locked the sheet. Open weeks are ignored even when the
/// sheet is locked, and an unlocked sheet on a locked week is ignored. That
/// keeps a commissioner-loaded pick list from leaking onto someone else's profile.
enum LeagueMemberProfilePolicy {
    static let bestWeekLimit = 3
    /// Same order of magnitude as Stats / Rivalry (`fetchPastWeeks` limit 20).
    static let weekReadLimit = 24

    struct PickSheet: Equatable {
        var isLocked: Bool
        var picks: [String: String]
        var confidenceGameId: String?
    }

    struct WeekInput: Equatable {
        var weekId: String
        var seasonYear: Int
        var weekNumber: Int
        var status: WeekStatus
        var pickMode: PickMode
        var pick: PickSheet?
        var games: [SlateGame]
    }

    struct FinishedWeek: Equatable, Identifiable {
        var weekId: String
        var seasonYear: Int
        var weekNumber: Int
        var wins: Int
        var losses: Int
        var pushes: Int

        var id: String { weekId }

        var label: String {
            "\(seasonYear.pickemsYearString) · Week \(weekNumber)"
        }

        var recordLabel: String {
            LeagueMemberProfilePolicy.recordLabel(wins: wins, losses: losses, pushes: pushes)
        }
    }

    struct TeamTally: Equatable, Identifiable {
        var teamId: String
        var name: String
        var abbreviation: String
        var logoURL: String?
        var count: Int

        var id: String { teamId }
    }

    struct HeadToHead: Equatable {
        var viewerWeekWins: Int
        var memberWeekWins: Int
        var ties: Int
        var weeksCompared: Int
    }

    struct CareerTotals: Equatable {
        var wins: Int
        var losses: Int
        var seasons: Int
        var titles: Int
        var bestFinish: Int?
        /// Closed seasons or a non-zero career record. A brand-new member is false.
        var hasClosedHistory: Bool

        var recordLabel: String {
            LeagueMemberProfilePolicy.recordLabel(wins: wins, losses: losses, pushes: 0)
        }
    }

    struct Snapshot: Equatable {
        var bestWeeks: [FinishedWeek]
        var winningWeeks: Int
        var streak: Int
        var mostPicked: TeamTally?
        var headToHead: HeadToHead?
        var failed: Bool

        static let empty = Snapshot(
            bestWeeks: [],
            winningWeeks: 0,
            streak: 0,
            mostPicked: nil,
            headToHead: nil,
            failed: false
        )
    }

    static func recordLabel(wins: Int, losses: Int, pushes: Int) -> String {
        if pushes > 0 {
            return "\(wins)–\(losses)–\(pushes)"
        }
        return "\(wins)–\(losses)"
    }

    /// Locked or final sheets only. `nil` when there is nothing to summarize.
    static func canSummarize(status: WeekStatus, pick: PickSheet?) -> Bool {
        guard let pick else { return false }
        switch status {
        case .scored:
            return true
        case .locked:
            return pick.isLocked
        case .selection, .picking:
            return false
        }
    }

    static func finishedWeeks(from weeks: [WeekInput]) -> [FinishedWeek] {
        var seen: Set<String> = []
        var finished: [FinishedWeek] = []
        for week in weeks {
            guard week.status == .scored,
                  canSummarize(status: week.status, pick: week.pick),
                  let pick = week.pick else {
                continue
            }
            let scored = ScoringEngine.scorePicks(
                picks: pick.picks,
                games: week.games,
                confidenceGameId: pick.confidenceGameId,
                pickMode: week.pickMode
            )
            guard scored.wins + scored.losses + scored.pushes > 0,
                  seen.insert(week.weekId).inserted else {
                continue
            }
            finished.append(
                FinishedWeek(
                    weekId: week.weekId,
                    seasonYear: week.seasonYear,
                    weekNumber: week.weekNumber,
                    wins: scored.wins,
                    losses: scored.losses,
                    pushes: scored.pushes
                )
            )
        }
        return finished
    }

    /// Highest win total, then fewer losses, then fewer pushes. Newest season and week break the rest.
    static func bestWeeks(_ weeks: [FinishedWeek], limit: Int = bestWeekLimit) -> [FinishedWeek] {
        guard limit > 0 else { return [] }
        let ranked = weeks.sorted { lhs, rhs in
            if lhs.wins != rhs.wins { return lhs.wins > rhs.wins }
            if lhs.losses != rhs.losses { return lhs.losses < rhs.losses }
            if lhs.pushes != rhs.pushes { return lhs.pushes < rhs.pushes }
            if lhs.seasonYear != rhs.seasonYear { return lhs.seasonYear > rhs.seasonYear }
            return lhs.weekNumber > rhs.weekNumber
        }
        return Array(ranked.prefix(limit))
    }

    static func winningWeekCount(_ weeks: [FinishedWeek]) -> Int {
        weeks.filter { $0.wins > $0.losses }.count
    }

    /// Winning weeks in a row, oldest season first. A tie or a losing week stops the run.
    static func streak(from weeks: [FinishedWeek]) -> Int {
        let ordered = weeks.sorted { lhs, rhs in
            if lhs.seasonYear != rhs.seasonYear { return lhs.seasonYear < rhs.seasonYear }
            return lhs.weekNumber < rhs.weekNumber
        }
        let records = ordered.map { WeeklyRecord(week: $0.weekNumber, wins: $0.wins, losses: $0.losses) }
        return StreakEngine.currentWinStreak(weeklyRecords: records)
    }

    /// One count per locked or final pick. Unknown team ids are dropped.
    static func mostPickedTeam(from weeks: [WeekInput]) -> TeamTally? {
        struct Accumulator {
            var name: String
            var abbreviation: String
            var logoURL: String?
            var count: Int
        }
        var totals: [String: Accumulator] = [:]
        for week in weeks {
            guard canSummarize(status: week.status, pick: week.pick), let pick = week.pick else { continue }
            for (gameId, teamId) in pick.picks {
                guard let game = week.games.first(where: { $0.id == gameId }),
                      let side = team(on: game, id: teamId) else {
                    continue
                }
                var current = totals[teamId] ?? Accumulator(
                    name: side.name,
                    abbreviation: side.abbreviation,
                    logoURL: side.logoURL,
                    count: 0
                )
                current.count += 1
                if current.name.isEmpty { current.name = side.name }
                if current.abbreviation.isEmpty { current.abbreviation = side.abbreviation }
                if current.logoURL == nil { current.logoURL = side.logoURL }
                totals[teamId] = current
            }
        }
        let ranked = totals.map { teamId, value in
            TeamTally(
                teamId: teamId,
                name: value.name,
                abbreviation: value.abbreviation,
                logoURL: value.logoURL,
                count: value.count
            )
        }
        return ranked.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            let abbreviation = lhs.abbreviation.localizedCaseInsensitiveCompare(rhs.abbreviation)
            if abbreviation != .orderedSame { return abbreviation == .orderedAscending }
            return lhs.teamId < rhs.teamId
        }.first
    }

    /// Viewer is side A. Weeks only one of them finished are left out.
    static func headToHead(memberWeeks: [FinishedWeek], viewerWeeks: [FinishedWeek]) -> HeadToHead? {
        let viewerById = Dictionary(viewerWeeks.map { ($0.weekId, $0) }, uniquingKeysWith: { first, _ in first })
        let rows: [(weekId: String, aWins: Int, aLosses: Int, bWins: Int, bLosses: Int)] = memberWeeks.compactMap { week in
            guard let viewer = viewerById[week.weekId] else { return nil }
            return (week.weekId, viewer.wins, viewer.losses, week.wins, week.losses)
        }
        guard !rows.isEmpty else { return nil }
        let result = RivalryEngine.headToHead(userAId: "viewer", userBId: "member", weekResults: rows)
        return HeadToHead(
            viewerWeekWins: result.userAWins,
            memberWeekWins: result.userBWins,
            ties: result.ties,
            weeksCompared: result.weeksCompared
        )
    }

    /// Closed-season career plus this season's member record. Someone who left does not get the live season added again.
    static func careerTotals(
        closed: CareerRecord?,
        currentWins: Int,
        currentLosses: Int,
        isCurrentMember: Bool
    ) -> CareerTotals {
        let baseWins = closed?.seasonWins ?? 0
        let baseLosses = closed?.seasonLosses ?? 0
        let baseSeasons = closed?.seasonsPlayed ?? 0
        return CareerTotals(
            wins: baseWins + (isCurrentMember ? currentWins : 0),
            losses: baseLosses + (isCurrentMember ? currentLosses : 0),
            seasons: baseSeasons + (isCurrentMember ? 1 : 0),
            titles: closed?.titles ?? 0,
            bestFinish: closed?.bestFinish,
            hasClosedHistory: baseSeasons > 0 || baseWins + baseLosses > 0
        )
    }

    /// Current roster or a career row already stored for this league. Anyone else is out.
    static func isLeagueSubject<Members: Sequence, Careers: Sequence>(
        userId: String,
        memberIds: Members,
        careerIds: Careers
    ) -> Bool where Members.Element == String, Careers.Element == String {
        if Set(memberIds).contains(userId) { return true }
        return Set(careerIds).contains(userId)
    }

    static func makeSnapshot(memberWeeks: [WeekInput], viewerWeeks: [WeekInput]) -> Snapshot {
        let finished = finishedWeeks(from: memberWeeks)
        let viewerFinished = finishedWeeks(from: viewerWeeks)
        return Snapshot(
            bestWeeks: bestWeeks(finished),
            winningWeeks: winningWeekCount(finished),
            streak: streak(from: finished),
            mostPicked: mostPickedTeam(from: memberWeeks),
            headToHead: headToHead(memberWeeks: finished, viewerWeeks: viewerFinished),
            failed: false
        )
    }

    private static func team(
        on game: SlateGame,
        id: String
    ) -> (name: String, abbreviation: String, logoURL: String?)? {
        if id == game.homeTeamId {
            return (game.homeTeamName, game.homeTeamAbbreviation, game.homeTeamLogoURL)
        }
        if id == game.awayTeamId {
            return (game.awayTeamName, game.awayTeamAbbreviation, game.awayTeamLogoURL)
        }
        return nil
    }
}

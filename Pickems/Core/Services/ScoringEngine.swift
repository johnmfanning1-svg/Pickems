import Foundation

enum ScoringEngine {
    static func isPickCorrect(pickedTeamId: String, game: SlateGame) -> Bool? {
        guard game.status == .final,
              let homeScore = game.homeScore,
              let awayScore = game.awayScore else {
            return nil
        }
        guard let coveredTeamId = game.coveredTeamId(homeScore: homeScore, awayScore: awayScore) else {
            return nil
        }
        return pickedTeamId == coveredTeamId
    }

    static func scorePicks(
        picks: [String: String],
        games: [SlateGame],
        confidenceGameId: String? = nil
    ) -> (wins: Int, losses: Int, pushes: Int) {
        var wins = 0
        var losses = 0
        var pushes = 0
        let gamesById = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })

        for (gameId, pickedTeamId) in picks {
            guard let game = gamesById[gameId] else { continue }
            let weight = (confidenceGameId == gameId) ? 2 : 1
            switch isPickCorrect(pickedTeamId: pickedTeamId, game: game) {
            case .some(true): wins += weight
            case .some(false): losses += weight
            case .none: pushes += 1
            }
        }
        return (wins, losses, pushes)
    }

    static func headToHeadPoints(
        userA: String,
        userB: String,
        picksByUser: [String: [String: String]],
        games: [SlateGame]
    ) -> (a: Int, b: Int) {
        var aPoints = 0
        var bPoints = 0

        for game in games {
            guard let pickA = picksByUser[userA]?[game.id],
                  let pickB = picksByUser[userB]?[game.id],
                  pickA != pickB else { continue }

            switch isPickCorrect(pickedTeamId: pickA, game: game) {
            case .some(true): aPoints += 1
            case .some(false): break
            case .none: break
            }
            switch isPickCorrect(pickedTeamId: pickB, game: game) {
            case .some(true): bPoints += 1
            case .some(false): break
            case .none: break
            }
        }

        return (aPoints, bPoints)
    }

    static func headToHeadRecord(
        userId: String,
        opponents: [String],
        picksByUser: [String: [String: String]],
        games: [SlateGame]
    ) -> Int {
        var wins = 0
        for opponent in opponents where opponent != userId {
            let h2h = headToHeadPoints(
                userA: userId,
                userB: opponent,
                picksByUser: picksByUser,
                games: games
            )
            if h2h.a > h2h.b { wins += 1 }
        }
        return wins
    }

    static func rankedStandings(
        entries: [StandingEntry],
        weekly: Bool,
        tieBreaker: TieBreakerPolicy,
        allPicks: [UserPick] = [],
        games: [SlateGame] = []
    ) -> [StandingEntry] {
        let picksByUser = Dictionary(uniqueKeysWithValues: allPicks.map { ($0.userId, $0.picks) })
        let hasAnyWins = entries.contains { (weekly ? $0.weeklyWins : $0.seasonWins) > 0 }

        var sorted: [StandingEntry]
        if hasAnyWins {
            sorted = entries.sorted { lhs, rhs in
                compareEntries(lhs, rhs, weekly: weekly, tieBreaker: tieBreaker, picksByUser: picksByUser, games: games)
            }

            if tieBreaker == .headToHead, !allPicks.isEmpty, !games.isEmpty {
                sorted = resolveHeadToHeadTieGroups(
                    sorted,
                    weekly: weekly,
                    picksByUser: picksByUser,
                    games: games
                )
            }
        } else {
            // Interim ranking: no wins yet → join order, then display name.
            sorted = entries.sorted(by: compareJoinDateThenName)
        }

        var ranked: [StandingEntry] = []
        for (index, var entry) in sorted.enumerated() {
            entry.rank = index + 1
            if index > 0 {
                let prev = ranked[index - 1]
                if hasAnyWins {
                    entry.isTied = entriesAreTied(
                        entry,
                        prev,
                        weekly: weekly,
                        tieBreaker: tieBreaker,
                        picksByUser: picksByUser,
                        games: games
                    )
                    if entry.isTied && tieBreaker == .commissionerOverride {
                        entry.rank = prev.rank
                    }
                } else {
                    // Distinct join dates produce distinct ranks; same join instant can tie.
                    entry.isTied = sameJoinInstant(entry, prev)
                    if entry.isTied {
                        entry.rank = prev.rank
                    }
                }
            } else {
                entry.isTied = false
            }
            ranked.append(entry)
        }
        return ranked
    }

    private static func compareEntries(
        _ lhs: StandingEntry,
        _ rhs: StandingEntry,
        weekly: Bool,
        tieBreaker: TieBreakerPolicy,
        picksByUser: [String: [String: String]],
        games: [SlateGame]
    ) -> Bool {
        let lhsWins = weekly ? lhs.weeklyWins : lhs.seasonWins
        let rhsWins = weekly ? rhs.weeklyWins : rhs.seasonWins
        if lhsWins != rhsWins { return lhsWins > rhsWins }

        let lhsAvg = weekly ? lhs.weeklyBattingAverage : lhs.seasonBattingAverage
        let rhsAvg = weekly ? rhs.weeklyBattingAverage : rhs.seasonBattingAverage
        if lhsAvg != rhsAvg { return lhsAvg > rhsAvg }

        if tieBreaker == .headToHead, !picksByUser.isEmpty, !games.isEmpty {
            let h2h = headToHeadPoints(
                userA: lhs.id,
                userB: rhs.id,
                picksByUser: picksByUser,
                games: games
            )
            if h2h.a != h2h.b { return h2h.a > h2h.b }
        }

        return compareJoinDateThenName(lhs, rhs)
    }

    /// Earlier join ranks higher; display name is the final stabilizer.
    private static func compareJoinDateThenName(_ lhs: StandingEntry, _ rhs: StandingEntry) -> Bool {
        let lhsDate = lhs.joinedAt ?? .distantFuture
        let rhsDate = rhs.joinedAt ?? .distantFuture
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func sameJoinInstant(_ lhs: StandingEntry, _ rhs: StandingEntry) -> Bool {
        switch (lhs.joinedAt, rhs.joinedAt) {
        case let (l?, r?): return l == r
        case (nil, nil): return true
        default: return false
        }
    }

    private static func resolveHeadToHeadTieGroups(
        _ entries: [StandingEntry],
        weekly: Bool,
        picksByUser: [String: [String: String]],
        games: [SlateGame]
    ) -> [StandingEntry] {
        var result: [StandingEntry] = []
        var index = 0

        while index < entries.count {
            var groupEnd = index + 1
            while groupEnd < entries.count,
                  samePrimaryRecord(entries[index], entries[groupEnd], weekly: weekly) {
                groupEnd += 1
            }

            let group = Array(entries[index..<groupEnd])
            if group.count > 1 {
                let opponentIds = group.map(\.id)
                let resolved = group.sorted { lhs, rhs in
                    let lhsRecord = headToHeadRecord(
                        userId: lhs.id,
                        opponents: opponentIds,
                        picksByUser: picksByUser,
                        games: games
                    )
                    let rhsRecord = headToHeadRecord(
                        userId: rhs.id,
                        opponents: opponentIds,
                        picksByUser: picksByUser,
                        games: games
                    )
                    if lhsRecord != rhsRecord { return lhsRecord > rhsRecord }
                    return compareJoinDateThenName(lhs, rhs)
                }
                result.append(contentsOf: resolved)
            } else {
                result.append(group[0])
            }

            index = groupEnd
        }

        return result
    }

    private static func samePrimaryRecord(_ lhs: StandingEntry, _ rhs: StandingEntry, weekly: Bool) -> Bool {
        if weekly {
            return lhs.weeklyWins == rhs.weeklyWins
                && lhs.weeklyBattingAverage == rhs.weeklyBattingAverage
        }
        return lhs.seasonWins == rhs.seasonWins
            && lhs.seasonBattingAverage == rhs.seasonBattingAverage
    }

    private static func entriesAreTied(
        _ lhs: StandingEntry,
        _ rhs: StandingEntry,
        weekly: Bool,
        tieBreaker: TieBreakerPolicy,
        picksByUser: [String: [String: String]],
        games: [SlateGame]
    ) -> Bool {
        guard samePrimaryRecord(lhs, rhs, weekly: weekly) else { return false }

        if tieBreaker == .headToHead, !picksByUser.isEmpty, !games.isEmpty {
            let opponentIds = [lhs.id, rhs.id]
            let lhsRecord = headToHeadRecord(
                userId: lhs.id,
                opponents: opponentIds,
                picksByUser: picksByUser,
                games: games
            )
            let rhsRecord = headToHeadRecord(
                userId: rhs.id,
                opponents: opponentIds,
                picksByUser: picksByUser,
                games: games
            )
            return lhsRecord == rhsRecord
        }

        return true
    }

    /// True when unique nominations have hit the week's expected slate size.
    static func isSlateComplete(nominationCount: Int, slateSize: Int) -> Bool {
        nominationCount >= slateSize
    }

    /// Member-mode completion: every active member hit their quota, or unique noms filled the week target.
    static func isMemberNominationRoundComplete(
        nominationsByUser: [String: Int],
        memberIds: [String],
        selectionsPerMember: Int,
        uniqueNominationCount: Int,
        slateSize: Int
    ) -> Bool {
        if isSlateComplete(nominationCount: uniqueNominationCount, slateSize: slateSize) {
            return true
        }
        guard !memberIds.isEmpty, selectionsPerMember > 0 else { return false }
        return memberIds.allSatisfy { (nominationsByUser[$0] ?? 0) >= selectionsPerMember }
    }

    static func canSubmitNomination(
        userNominationCount: Int,
        selectionsPerMember: Int,
        uniqueNominationCount: Int,
        slateSize: Int,
        selectionDeadline: Date?,
        now: Date = Date()
    ) -> Bool {
        if let selectionDeadline, now >= selectionDeadline { return false }
        return userNominationCount < selectionsPerMember && uniqueNominationCount < slateSize
    }

    static func isPastDeadline(deadline: Date?) -> Bool {
        PickDeadlineCalculator.isPast(deadline)
    }
}

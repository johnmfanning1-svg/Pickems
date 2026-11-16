import Foundation

struct SeasonLedgerMemberRecord: Equatable, Sendable {
    var wins: Int
    var losses: Int
    var pushes: Int

    static let zero = SeasonLedgerMemberRecord(wins: 0, losses: 0, pushes: 0)

    mutating func add(_ other: SeasonLedgerMemberRecord) {
        wins += other.wins
        losses += other.losses
        pushes += other.pushes
    }
}

struct SeasonLedgerWeekBoard: Identifiable, Equatable, Sendable {
    var id: String { week.id }
    let week: WeekSummary
    let games: [SlateGame]
    let picksByUserId: [String: UserPick]
    let hiddenGameIds: Set<String>
    let recordsByMemberId: [String: SeasonLedgerMemberRecord]
    let pickMode: PickMode

    var weeklyWinsByMemberId: [String: Int] {
        recordsByMemberId.mapValues(\.wins)
    }
}

struct SeasonLedgerSeasonData: Equatable, Sendable {
    let groupId: String
    let weeks: [SeasonLedgerWeekBoard]
    let memberIds: [String]

    func seasonRecord(for memberId: String) -> SeasonLedgerMemberRecord {
        var total = SeasonLedgerMemberRecord.zero
        for week in weeks {
            if let record = week.recordsByMemberId[memberId] {
                total.add(record)
            }
        }
        return total
    }

    func seasonWinsByMemberId() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: memberIds.map { id in
            (id, seasonRecord(for: id).wins)
        })
    }
}

enum SeasonLedgerAggregator {
    static func memberRecords(
        members: [GroupMember],
        games: [SlateGame],
        picksByUserId: [String: UserPick],
        hiddenGameIds: Set<String>,
        viewerId: String?,
        pickMode: PickMode
    ) -> [String: SeasonLedgerMemberRecord] {
        var result: [String: SeasonLedgerMemberRecord] = [:]
        for member in members {
            let pick = picksByUserId[member.id]
            let gamesForMember: [SlateGame] = member.id == viewerId
                ? games
                : games.filter { !hiddenGameIds.contains($0.id) }
            let scored = ScoringEngine.scorePicks(
                picks: pick?.picks ?? [:],
                games: gamesForMember,
                confidenceGameId: pick?.confidenceGameId,
                submittedAt: pick?.submittedAt,
                deadline: nil,
                latePenaltyWins: 0,
                pickMode: pickMode
            )
            result[member.id] = SeasonLedgerMemberRecord(
                wins: scored.wins,
                losses: scored.losses,
                pushes: scored.pushes
            )
        }
        return result
    }

    static func pickCellStatus(
        game: SlateGame,
        pickedTeamId: String?,
        pickMode: PickMode
    ) -> PickBoardStatus {
        ScoringEngine.pickBoardStatus(
            pickedTeamId: pickedTeamId,
            game: game,
            pickMode: pickMode
        )
    }
}
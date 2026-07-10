import Foundation

struct SeasonStandingEntry: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var avatarColorHex: String
    var seasonWins: Int
    var seasonLosses: Int
    var rank: Int

    var battingAverage: Double {
        BattingAverage.rate(wins: seasonWins, losses: seasonLosses)
    }
}

struct SeasonArchive: Codable, Identifiable, Equatable {
    var id: String
    var seasonYear: Int
    var groupId: String
    var championUserId: String?
    var championDisplayName: String?
    var finalStandings: [SeasonStandingEntry]
    var weekCount: Int
    var closedAt: Date

    init(
        seasonYear: Int,
        groupId: String,
        championUserId: String?,
        championDisplayName: String?,
        finalStandings: [SeasonStandingEntry],
        weekCount: Int,
        closedAt: Date = Date()
    ) {
        self.id = String(seasonYear)
        self.seasonYear = seasonYear
        self.groupId = groupId
        self.championUserId = championUserId
        self.championDisplayName = championDisplayName
        self.finalStandings = finalStandings
        self.weekCount = weekCount
        self.closedAt = closedAt
    }
}

struct CareerRecord: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var avatarColorHex: String
    var titles: Int
    var seasonWins: Int
    var seasonLosses: Int
    var seasonsPlayed: Int
    var bestFinish: Int?
    var updatedAt: Date

    var battingAverage: Double {
        BattingAverage.rate(wins: seasonWins, losses: seasonLosses)
    }

    var recordLabel: String {
        "\(seasonWins)-\(seasonLosses)"
    }
}

enum SeasonCloseEngine {
    static func finalStandings(from members: [GroupMember]) -> [SeasonStandingEntry] {
        let ranked = members.sorted {
            if $0.seasonWins != $1.seasonWins { return $0.seasonWins > $1.seasonWins }
            if $0.battingAverage != $1.battingAverage { return $0.battingAverage > $1.battingAverage }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        return ranked.enumerated().map { index, member in
            SeasonStandingEntry(
                id: member.id,
                displayName: member.displayName,
                avatarColorHex: member.avatarColorHex,
                seasonWins: member.seasonWins,
                seasonLosses: member.seasonLosses,
                rank: index + 1
            )
        }
    }

    static func makeArchive(
        seasonYear: Int,
        groupId: String,
        members: [GroupMember],
        weekCount: Int,
        closedAt: Date = Date()
    ) -> SeasonArchive {
        let standings = finalStandings(from: members)
        let champion = standings.first
        return SeasonArchive(
            seasonYear: seasonYear,
            groupId: groupId,
            championUserId: champion?.id,
            championDisplayName: champion?.displayName,
            finalStandings: standings,
            weekCount: weekCount,
            closedAt: closedAt
        )
    }

    static func updatedCareer(
        existing: CareerRecord?,
        member: GroupMember,
        finish: Int,
        wonTitle: Bool,
        now: Date = Date()
    ) -> CareerRecord {
        let base = existing ?? CareerRecord(
            id: member.id,
            displayName: member.displayName,
            avatarColorHex: member.avatarColorHex,
            titles: 0,
            seasonWins: 0,
            seasonLosses: 0,
            seasonsPlayed: 0,
            bestFinish: nil,
            updatedAt: now
        )

        let bestFinish: Int?
        if let currentBest = base.bestFinish {
            bestFinish = min(currentBest, finish)
        } else {
            bestFinish = finish
        }

        return CareerRecord(
            id: member.id,
            displayName: member.displayName,
            avatarColorHex: member.avatarColorHex,
            titles: base.titles + (wonTitle ? 1 : 0),
            seasonWins: base.seasonWins + member.seasonWins,
            seasonLosses: base.seasonLosses + member.seasonLosses,
            seasonsPlayed: base.seasonsPlayed + 1,
            bestFinish: bestFinish,
            updatedAt: now
        )
    }
}

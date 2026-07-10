import Foundation

struct UserProfile: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var avatarColorHex: String
    var avatarImageURL: String?
    var favoriteTeamId: String? = nil
    var favoriteTeamName: String? = nil
    var favoriteTeamAbbreviation: String? = nil
    var favoriteTeamLogoURL: String? = nil
    var createdAt: Date

    var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var favoriteTeam: FavoriteTeam? {
        TeamThemeCatalog.team(id: favoriteTeamId)
    }
}

struct PickemGroup: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var inviteCode: String
    var commissionerId: String
    var memberIds: [String]
    var rules: GroupRules
    var createdAt: Date

    var memberCount: Int { memberIds.count }
}

struct GroupMember: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var avatarColorHex: String
    var role: MemberRole
    var joinedAt: Date
    var seasonWins: Int
    var seasonLosses: Int

    enum MemberRole: String, Codable {
        case commissioner
        case member
    }

    var battingAverage: Double {
        BattingAverage.rate(wins: seasonWins, losses: seasonLosses)
    }
}

struct WeekSummary: Codable, Identifiable, Equatable {
    var id: String
    var seasonYear: Int
    var weekNumber: Int
    var status: WeekStatus
    var slateSize: Int
    var selectionMode: SelectionMode
    var selectionsPerMember: Int
    var lockedAt: Date?
    var pickDeadline: Date?
    var nominationCount: Int

    var displayLabel: String {
        "Season \(seasonYear) | Week \(weekNumber)"
    }
}

struct SlateGame: Codable, Identifiable, Equatable {
    var id: String
    var espnEventId: String
    var homeTeamId: String
    var homeTeamName: String
    var homeTeamAbbreviation: String
    var homeTeamLogoURL: String?
    var awayTeamId: String
    var awayTeamName: String
    var awayTeamAbbreviation: String
    var awayTeamLogoURL: String?
    var spread: Double
    var spreadTeamId: String
    var kickoff: Date
    var status: GameStatus
    var homeScore: Int?
    var awayScore: Int?
    var winnerTeamId: String?

    enum GameStatus: String, Codable {
        case scheduled
        case inProgress
        case final
    }

    func spreadLabel(for teamId: String) -> String {
        let isFavorite = teamId == spreadTeamId
        let value = abs(spread)
        let sign = isFavorite ? "-" : "+"
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(1))))"
    }

    func coveredTeamId(homeScore: Int, awayScore: Int) -> String? {
        let spreadMagnitude = abs(spread)
        let margin = Double(homeScore - awayScore)
        let adjusted = margin + (spreadTeamId == homeTeamId ? -spreadMagnitude : spreadMagnitude)
        if adjusted == 0 { return nil }
        return adjusted > 0 ? homeTeamId : awayTeamId
    }
}

struct Nomination: Codable, Identifiable, Equatable {
    var id: String
    var submittedBy: String
    var submitterName: String
    var espnEventId: String
    var spread: Double
    var spreadTeamId: String
    var homeTeamName: String
    var awayTeamName: String
    var kickoff: Date
    var createdAt: Date
}

struct UserPick: Codable, Identifiable, Equatable {
    var id: String
    var userId: String
    var displayName: String
    var picks: [String: String]
    var submittedAt: Date?
    var isLocked: Bool
}

/// Public submission metadata — readable by all group members before the pick deadline.
struct PickSubmission: Codable, Identifiable, Equatable {
    var id: String
    var userId: String
    var displayName: String
    var isLocked: Bool
    var submittedAt: Date?
}

struct StandingEntry: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var avatarColorHex: String
    var weeklyWins: Int
    var weeklyLosses: Int
    var seasonWins: Int
    var seasonLosses: Int
    var rank: Int
    var isTied: Bool

    var weeklyBattingAverage: Double {
        BattingAverage.rate(wins: weeklyWins, losses: weeklyLosses)
    }

    var seasonBattingAverage: Double {
        BattingAverage.rate(wins: seasonWins, losses: seasonLosses)
    }
}

struct GroupStandings: Codable, Equatable {
    var groupId: String
    var weekNumber: Int
    var entries: [StandingEntry]
    var updatedAt: Date
}

struct WeekHistoryEntry: Identifiable, Equatable {
    let id: String
    let week: WeekSummary
    let userPick: UserPick?
    let slateGames: [SlateGame]
}

struct ESPNNewsItem: Identifiable, Equatable {
    let id: String
    let headline: String
    let description: String?
    let imageURL: String?
    let publishedAt: Date
    let link: URL?
}

struct WeeklyRecord: Equatable, Identifiable {
    var id: Int { week }
    let week: Int
    let wins: Int
    let losses: Int
}

struct PlayerSeasonStats: Identifiable {
    let id: String
    let displayName: String
    let weeklyRecords: [WeeklyRecord]
    let seasonWins: Int
    let seasonLosses: Int
    let currentStreak: Int
    let bestWeekNumber: Int?
    let bestWeekWins: Int?
    let bestWeekLosses: Int?
}

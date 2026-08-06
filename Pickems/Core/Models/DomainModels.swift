import Foundation

struct UserProfile: Codable, Identifiable, Equatable {
    var id: String
    /// Unique public username / handle shown in leagues.
    var displayName: String
    var firstName: String? = nil
    var lastName: String? = nil
    /// Normalized uniqueness key for `handles/{handleKey}` (lowercase username).
    var handleKey: String? = nil
    var avatarColorHex: String
    var avatarImageURL: String?
    var favoriteTeamId: String? = nil
    var favoriteTeamName: String? = nil
    var favoriteTeamAbbreviation: String? = nil
    var favoriteTeamLogoURL: String? = nil
    var createdAt: Date

    var fullName: String? {
        let first = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let joined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    var initials: String {
        if let first = firstName?.first, let last = lastName?.first {
            return "\(first)\(last)".uppercased()
        }
        if let first = firstName?.prefix(2), !first.isEmpty {
            return String(first).uppercased()
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(2)).uppercased()
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
    /// When true, league appears in Discover for anyone signed in.
    var isPublic: Bool = false

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
    /// Profile photo URL mirrored from `users/{uid}.avatarImageURL` when set.
    var avatarImageURL: String? = nil

    enum MemberRole: String, Codable {
        case commissioner
        case member
    }

    var battingAverage: Double {
        BattingAverage.rate(wins: seasonWins, losses: seasonLosses)
    }

    var initials: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(2)).uppercased()
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
    var awards: WeekAwards? = nil

    var displayLabel: String {
        "Season \(seasonYear.pickemsYearString) | Week \(weekNumber)"
    }
}

struct WeekAwards: Codable, Equatable {
    var sharpshooterUserId: String?
    var heartbreakerUserId: String?
    var contrarianUserId: String?
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
    var homeTeamId: String?
    var homeTeamName: String
    var homeTeamAbbreviation: String?
    var homeTeamLogoURL: String?
    var awayTeamId: String?
    var awayTeamName: String
    var awayTeamAbbreviation: String?
    var awayTeamLogoURL: String?
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
    /// Optional double-weight game when confidence picks are enabled.
    var confidenceGameId: String? = nil
}

/// Public submission metadata — readable by all group members before the pick deadline.
struct PickSubmission: Codable, Identifiable, Equatable {
    var id: String
    var userId: String
    var displayName: String
    var isLocked: Bool
    var submittedAt: Date?
    /// Number of games picked — public so Group Picks can show 3/3 before week lock
    /// without revealing which teams were chosen.
    var pickCount: Int = 0
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
    /// Used for interim ranking (no wins yet) and as a tiebreaker before display name.
    var joinedAt: Date? = nil
    var avatarImageURL: String? = nil

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

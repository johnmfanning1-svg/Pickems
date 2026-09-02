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
    /// Opt-in alerts. Nil (legacy docs) means on so existing users keep receiving them.
    var notifySelectionDeadlines: Bool? = true
    var notifyPickemsDeadlines: Bool? = true
    var notifyGameFinals: Bool? = true
    var notifyTookTheLead: Bool? = true
    var notifyWeekScored: Bool? = true
    var notifySeasonClosed: Bool? = true
    var notifyChatMessages: Bool? = true

    var wantsSelectionDeadlineAlerts: Bool { wants(.selectionDeadlines) }
    var wantsPickemsDeadlineAlerts: Bool { wants(.pickemsDeadlines) }

    func wants(_ category: NotificationPrefCategory) -> Bool {
        switch category {
        case .selectionDeadlines: return notifySelectionDeadlines ?? true
        case .pickemsDeadlines: return notifyPickemsDeadlines ?? true
        case .gameFinals: return notifyGameFinals ?? true
        case .tookTheLead: return notifyTookTheLead ?? true
        case .weekScored: return notifyWeekScored ?? true
        case .seasonClosed: return notifySeasonClosed ?? true
        case .chatMessages: return notifyChatMessages ?? true
        }
    }

    mutating func set(_ category: NotificationPrefCategory, enabled: Bool) {
        switch category {
        case .selectionDeadlines: notifySelectionDeadlines = enabled
        case .pickemsDeadlines: notifyPickemsDeadlines = enabled
        case .gameFinals: notifyGameFinals = enabled
        case .tookTheLead: notifyTookTheLead = enabled
        case .weekScored: notifyWeekScored = enabled
        case .seasonClosed: notifySeasonClosed = enabled
        case .chatMessages: notifyChatMessages = enabled
        }
    }

    var enabledNotificationPrefCount: Int {
        NotificationPrefCategory.allCases.filter { wants($0) }.count
    }

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
    /// Private-league lock so only the commissioner can share the invite. Nil/missing means off.
    var commissionerOnlyInvites: Bool? = nil

    var memberCount: Int { memberIds.count }

    /// Private league whose commissioner turned on commissioner-only invites.
    var restrictsMemberInvites: Bool {
        !isPublic && commissionerOnlyInvites == true
    }

    func canShareInvite(asCommissioner isCommissioner: Bool) -> Bool {
        isCommissioner || !restrictsMemberInvites
    }
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
    /// Expected/max unique games for this week (derived in member mode at mint).
    var slateSize: Int
    var selectionMode: SelectionMode
    var selectionsPerMember: Int
    var lockedAt: Date?
    /// Spread-pick lock — earliest slate kickoff once picking opens.
    var pickDeadline: Date?
    var nominationCount: Int
    /// Commissioner-set deadline for member nominations (member mode).
    var selectionDeadline: Date? = nil
    var selectionDeadlineSetAt: Date? = nil
    var selectionDeadlineSetBy: String? = nil
    var awards: WeekAwards? = nil
    /// `"fixedBoard"` for auto-slated weeks (Week 0). Nil on nomination-built weeks.
    var slateSource: String? = nil

    var displayLabel: String {
        "Season \(seasonYear.pickemsYearString) | Week \(weekNumber)"
    }

    var skipsSelection: Bool {
        CFBWeekCalendar.isFixedSlate(weekNumber: weekNumber, slateSource: slateSource)
    }

    var espnScoreboardWeek: Int {
        CFBWeekCalendar.espnScoreboardWeek(weekNumber)
    }

    /// True when a selection deadline is set and has passed.
    var isSelectionDeadlinePassed: Bool {
        guard let selectionDeadline else { return false }
        return Date() >= selectionDeadline
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
    var broadcastLabel: String? = nil
    var isNeutralSite: Bool = false

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

    /// Home scoreboard format: `UVA -4.0`.
    var favoriteSpreadDisplay: String {
        let abbr = spreadTeamId == homeTeamId ? homeTeamAbbreviation : awayTeamAbbreviation
        return "\(abbr) \(spreadLabel(for: spreadTeamId))"
    }

    /// Which side the Pickems spread applies to. `nil` when there is no favorite.
    var favoredSide: TeamDisplay.FavoredSide? {
        guard abs(spread) > 0 else { return nil }
        if spreadTeamId == homeTeamId { return .home }
        if spreadTeamId == awayTeamId { return .away }
        return nil
    }

    func coveredTeamId(homeScore: Int, awayScore: Int) -> String? {
        let spreadMagnitude = abs(spread)
        let margin = Double(homeScore - awayScore)
        let adjusted = margin + (spreadTeamId == homeTeamId ? -spreadMagnitude : spreadMagnitude)
        if adjusted == 0 { return nil }
        return adjusted > 0 ? homeTeamId : awayTeamId
    }

    var matchupSeparator: String { isNeutralSite ? "vs" : "@" }

    var kickoffMetaLine: String {
        GameKickoffLine.make(kickoff: kickoff, broadcastLabel: broadcastLabel, includeDate: true)
    }
}

enum GameKickoffLine {
    enum DateStyle {
        case omitted
        case abbreviated
        case compactMonthDay
    }

    static func make(kickoff: Date, broadcastLabel: String?, includeDate: Bool) -> String {
        make(
            kickoff: kickoff,
            broadcastLabel: broadcastLabel,
            dateStyle: includeDate ? .abbreviated : .omitted
        )
    }

    static func make(
        kickoff: Date,
        broadcastLabel: String?,
        dateStyle: DateStyle,
        calendar: Calendar = .autoupdatingCurrent,
        includeBroadcast: Bool = true
    ) -> String {
        let time: String
        switch dateStyle {
        case .omitted:
            time = kickoff.formatted(date: .omitted, time: .shortened)
        case .abbreviated:
            time = kickoff.formatted(date: .abbreviated, time: .shortened)
        case .compactMonthDay:
            let clock = kickoff.formatted(date: .omitted, time: .shortened)
            time = "\(compactMonthDay(kickoff, calendar: calendar)) · \(clock)"
        }
        guard includeBroadcast else { return time }
        if let broadcastLabel {
            let trimmed = broadcastLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.uppercased() != "TBD" {
                return "\(time) · \(trimmed)"
            }
        }
        return time
    }

    /// `08/29` — month then day, for tight Home and chart cells.
    static func compactMonthDay(_ kickoff: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.day, .month], from: kickoff)
        return String(format: "%02d/%02d", parts.month ?? 0, parts.day ?? 0)
    }

    /// Network for Home tiles. Missing or ESPN `TBD` still shows `TBD`.
    static func networkLabel(_ broadcastLabel: String?) -> String {
        guard let broadcastLabel else { return "TBD" }
        let trimmed = broadcastLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "TBD" }
        return trimmed
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

    static func fromESPNGame(
        _ game: ESPNGame,
        id: String = "",
        submittedBy: String,
        submitterName: String,
        createdAt: Date = Date()
    ) -> Nomination {
        Nomination(
            id: id,
            submittedBy: submittedBy,
            submitterName: submitterName,
            espnEventId: game.espnEventId,
            spread: abs(game.spread ?? 0),
            spreadTeamId: game.spreadTeamId ?? game.homeTeamId,
            homeTeamId: game.homeTeamId,
            homeTeamName: game.homeTeamName,
            homeTeamAbbreviation: game.homeTeamAbbreviation,
            homeTeamLogoURL: game.homeTeamLogoURL,
            awayTeamId: game.awayTeamId,
            awayTeamName: game.awayTeamName,
            awayTeamAbbreviation: game.awayTeamAbbreviation,
            awayTeamLogoURL: game.awayTeamLogoURL,
            kickoff: game.kickoff,
            createdAt: createdAt
        )
    }
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

    static func placeholder(from member: GroupMember) -> StandingEntry {
        StandingEntry(
            id: member.id,
            displayName: member.displayName,
            avatarColorHex: member.avatarColorHex,
            weeklyWins: 0,
            weeklyLosses: 0,
            seasonWins: member.seasonWins,
            seasonLosses: member.seasonLosses,
            rank: 0,
            isTied: false,
            joinedAt: member.joinedAt,
            avatarImageURL: member.avatarImageURL
        )
    }
}

/// Standings documents can lag new members and keep people who left.
/// Rank the live roster: current members, with standings stats overlaid when present.
enum StandingBoard {
    /// `memberIds` on the group doc is membership. Drop orphan member docs.
    static func roster(members: [GroupMember], memberIds: [String]) -> [GroupMember] {
        guard !memberIds.isEmpty else { return members }
        let allowed = Set(memberIds)
        return members.filter { allowed.contains($0.id) }
    }

    static func baseEntries(
        standingsEntries: [StandingEntry]?,
        members: [GroupMember],
        memberIds: [String] = []
    ) -> [StandingEntry] {
        let roster = Self.roster(members: members, memberIds: memberIds)
        if roster.isEmpty {
            let entries = standingsEntries ?? []
            guard !memberIds.isEmpty else { return entries }
            let allowed = Set(memberIds)
            return entries.filter { allowed.contains($0.id) }
        }

        let joinedAtById = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0.joinedAt) })
        let avatarURLById = Dictionary(uniqueKeysWithValues: roster.compactMap { member -> (String, String)? in
            guard let url = member.avatarImageURL, !url.isEmpty else { return nil }
            return (member.id, url)
        })
        let standingsById = Dictionary(
            (standingsEntries ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )

        return roster.map { member in
            guard var entry = standingsById[member.id] else {
                return .placeholder(from: member)
            }
            if entry.joinedAt == nil {
                entry.joinedAt = joinedAtById[member.id]
            }
            if entry.avatarImageURL == nil {
                entry.avatarImageURL = avatarURLById[member.id]
            }
            return entry
        }
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

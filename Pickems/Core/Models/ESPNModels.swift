import Foundation

struct ESPNGame: Identifiable, Equatable {
    let id: String
    let espnEventId: String
    let competitionId: String
    let homeTeamId: String
    let homeTeamName: String
    let homeTeamAbbreviation: String
    let homeTeamLogoURL: String?
    let awayTeamId: String
    let awayTeamName: String
    let awayTeamAbbreviation: String
    let awayTeamLogoURL: String?
    let kickoff: Date
    let spread: Double?
    let spreadTeamId: String?
    let status: SlateGame.GameStatus
    let homeScore: Int?
    let awayScore: Int?
    /// nil when unranked; ESPN sends 99 for unranked → map to nil
    let homeCuratedRank: Int?
    let awayCuratedRank: Int?
    /// ESPN competitor.team.conferenceId
    let homeConferenceId: String?
    let awayConferenceId: String?
    var broadcastLabel: String? = nil
    var isNeutralSite: Bool = false
    /// ESPN live clock, e.g. `2nd 7:12` or `Halftime`. Nil when the game is not in progress.
    var liveClockLabel: String? = nil

    var isTop25: Bool { homeCuratedRank != nil || awayCuratedRank != nil }

    var matchupSeparator: String { isNeutralSite ? "vs" : "@" }

    var kickoffMetaLine: String {
        GameKickoffLine.make(kickoff: kickoff, broadcastLabel: broadcastLabel, includeDate: true)
    }
}

struct ESPNScoreboardResponse: Decodable {
    let events: [ESPNEvent]?
    let season: ESPNSeasonMeta?
    let week: ESPNWeekMeta?

    struct ESPNSeasonMeta: Decodable {
        let year: Int
        let type: Int
    }

    struct ESPNWeekMeta: Decodable {
        let number: Int
    }

    struct ESPNEvent: Decodable {
        let id: String
        let date: String
        let competitions: [ESPNCompetition]?
    }

    struct ESPNCompetition: Decodable {
        let id: String
        let competitors: [ESPNCompetitor]?
        let status: ESPNStatus?
        let odds: [ESPNOdds]?
        let broadcasts: [ESPNBroadcast]?
        let geoBroadcasts: [ESPNGeoBroadcast]?
        let neutralSite: Bool?
    }

    struct ESPNBroadcast: Decodable {
        let market: String?
        let names: [String]?
    }

    struct ESPNGeoBroadcast: Decodable {
        struct ESPNGeoMedia: Decodable {
            let shortName: String?
            let name: String?
        }

        let media: ESPNGeoMedia?
    }

    struct ESPNCompetitor: Decodable {
        let id: String
        let homeAway: String
        let team: ESPNTeam
        let score: String?
        let curatedRank: ESPNCuratedRank?
    }

    struct ESPNCuratedRank: Decodable {
        let current: Int
    }

    struct ESPNTeam: Decodable {
        let id: String
        let displayName: String
        let abbreviation: String
        let logo: String?
        let logos: [ESPNLogo]?
        let conferenceId: String?
    }

    struct ESPNLogo: Decodable {
        let href: String
    }

    struct ESPNStatus: Decodable {
        let type: ESPNStatusType
        let displayClock: String?
        let period: Int?
    }

    struct ESPNStatusType: Decodable {
        let completed: Bool
        let state: String
        let shortDetail: String?
        let detail: String?
    }

    struct ESPNOdds: Decodable {
        let spread: Double?
        let details: String?
        let homeTeamOdds: ESPNTeamOdds?
        let awayTeamOdds: ESPNTeamOdds?
    }

    struct ESPNTeamOdds: Decodable {
        let favorite: Bool?
    }
}

struct CFBWeekInfo: Equatable {
    let seasonYear: Int
    let weekNumber: Int
    let seasonType: Int
    let label: String
}

struct ESPNLiveGameCard: Identifiable, Equatable {
    let id: String
    let espnEventId: String
    let awayTeamId: String?
    let awayTeamName: String
    let awayTeamAbbreviation: String
    let awayTeamLogoURL: String?
    let homeTeamId: String?
    let homeTeamName: String
    let homeTeamAbbreviation: String
    let homeTeamLogoURL: String?
    let awayScore: Int?
    let homeScore: Int?
    let spreadLabel: String?
    let status: SlateGame.GameStatus
    let statusDetail: String
    let kickoff: Date
    let isSlateGame: Bool
    /// ESPN curated poll rank (1...25). `nil` when unranked.
    let homeCuratedRank: Int?
    let awayCuratedRank: Int?
    let homeConferenceId: String?
    let awayConferenceId: String?
    var broadcastLabel: String? = nil
    var isNeutralSite: Bool = false
    var userPickTeamAbbreviation: String?
    var pickResult: PickResult?
    /// ESPN's current line when `spreadLabel` is the locked Pickems slate line.
    var liveSpreadLabel: String? = nil

    enum PickResult: Equatable {
        case win, loss, push, pending
    }

    var hasUserPick: Bool { userPickTeamAbbreviation != nil || pickResult != nil }

    var isTop25: Bool { homeCuratedRank != nil || awayCuratedRank != nil }

    func curatedRank(forTeamId teamId: String) -> Int? {
        if teamId == homeTeamId { return homeCuratedRank }
        if teamId == awayTeamId { return awayCuratedRank }
        return nil
    }

    func matches(_ filter: HomeScoreboardFilter) -> Bool {
        switch filter {
        case .power4:
            return ESPNConferenceCatalog.isPower4(homeConferenceId)
                || ESPNConferenceCatalog.isPower4(awayConferenceId)
        case .top25:
            return isTop25
        case .all:
            return true
        case .myPicks:
            return hasUserPick
        case .groupSlate:
            return isSlateGame
        case .conference(let id):
            return homeConferenceId == id || awayConferenceId == id
        }
    }
}

extension ESPNGame {
    func toSlateGame(spreadOverride: Double? = nil, spreadTeamOverride: String? = nil) -> SlateGame {
        let rawSpread = spreadOverride ?? spread ?? 0
        // ESPN's numeric spread is home-centric (negative = home favored). `spreadTeamId`
        // already names the favorite from odds flags / details — do not invert it when
        // the number is negative or every home favorite becomes the away team.
        let spreadTeam = spreadTeamOverride ?? spreadTeamId ?? homeTeamId
        return SlateGame(
            id: espnEventId,
            espnEventId: espnEventId,
            homeTeamId: homeTeamId,
            homeTeamName: homeTeamName,
            homeTeamAbbreviation: homeTeamAbbreviation,
            homeTeamLogoURL: homeTeamLogoURL,
            awayTeamId: awayTeamId,
            awayTeamName: awayTeamName,
            awayTeamAbbreviation: awayTeamAbbreviation,
            awayTeamLogoURL: awayTeamLogoURL,
            spread: abs(rawSpread),
            spreadTeamId: spreadTeam,
            kickoff: kickoff,
            status: status,
            homeScore: homeScore,
            awayScore: awayScore,
            winnerTeamId: nil,
            broadcastLabel: broadcastLabel,
            isNeutralSite: isNeutralSite
        )
    }

    var spreadDisplayLabel: String? {
        guard let spread, let spreadTeamId else { return nil }
        let teamAbbr = spreadTeamId == homeTeamId ? homeTeamAbbreviation : awayTeamAbbreviation
        let magnitude = abs(spread).formatted(.number.precision(.fractionLength(1)))
        // Favorite (spreadTeamId) always shows as -line, matching SlateGame.spreadLabel.
        return "\(teamAbbr) -\(magnitude)"
    }
}

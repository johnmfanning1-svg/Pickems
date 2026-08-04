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

    var isTop25: Bool { homeCuratedRank != nil || awayCuratedRank != nil }
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
    }

    struct ESPNStatusType: Decodable {
        let completed: Bool
        let state: String
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
    let awayTeamName: String
    let awayTeamAbbreviation: String
    let awayTeamLogoURL: String?
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
    var userPickTeamAbbreviation: String?
    var pickResult: PickResult?

    enum PickResult: Equatable {
        case win, loss, push, pending
    }
}

extension ESPNGame {
    func toSlateGame(spreadOverride: Double? = nil, spreadTeamOverride: String? = nil) -> SlateGame {
        let rawSpread = spreadOverride ?? spread ?? 0
        var spreadTeam = spreadTeamOverride ?? spreadTeamId ?? homeTeamId
        if rawSpread < 0 {
            spreadTeam = spreadTeam == homeTeamId ? awayTeamId : homeTeamId
        }
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
            winnerTeamId: nil
        )
    }

    var spreadDisplayLabel: String? {
        guard let spread, let spreadTeamId else { return nil }
        let teamAbbr = spreadTeamId == homeTeamId ? homeTeamAbbreviation : awayTeamAbbreviation
        let sign = spread < 0 ? "" : "+"
        return "\(teamAbbr) \(sign)\(abs(spread).formatted(.number.precision(.fractionLength(1))))"
    }
}

import Foundation

enum ShareResultType: String, Codable {
    case weekly
    case seasonEnd
}

struct ShareableResult: Identifiable, Equatable {
    let id: String
    let type: ShareResultType
    let displayName: String
    let leagueName: String
    let season: Int
    let week: Int?
    let rank: Int
    let totalPlayers: Int
    let headline: String
    let statsLine: String
    let bragLine: String
    let promoURL: String

    init(weekly: WeeklyResult, tone: ShareTone = .auto) {
        id = "weekly-\(weekly.season)-\(weekly.week)-\(weekly.userId)"
        type = .weekly
        displayName = weekly.displayName
        leagueName = weekly.leagueName
        season = weekly.season
        week = weekly.week
        rank = weekly.rank
        totalPlayers = weekly.totalPlayers
        headline = ShareTextBuilder.weeklyHeadline(for: weekly)
        statsLine = ShareTextBuilder.weeklyStatsLine(for: weekly)
        bragLine = ShareTextBuilder.weeklyBragLine(for: weekly, tone: tone)
        promoURL = AppConfig.appPromoURL
    }

    init(season standing: SeasonStanding, tone: ShareTone = .auto) {
        id = "season-\(standing.season)-\(standing.userId)"
        type = .seasonEnd
        displayName = standing.displayName
        leagueName = standing.leagueName
        season = standing.season
        week = nil
        rank = standing.rank
        totalPlayers = standing.totalPlayers
        headline = ShareTextBuilder.seasonHeadline(for: standing)
        statsLine = ShareTextBuilder.seasonStatsLine(for: standing)
        bragLine = ShareTextBuilder.seasonBragLine(for: standing, tone: tone)
        promoURL = AppConfig.appPromoURL
    }

    var tweetText: String {
        ShareTextBuilder.composeTweet(for: self)
    }

    var messageText: String {
        ShareTextBuilder.composeMessage(for: self)
    }

    var shareSheetText: String {
        messageText
    }
}

enum ShareTone: String, CaseIterable, Identifiable {
    case auto
    case humbleBrag
    case fullDunk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .humbleBrag: return "Humble Brag"
        case .fullDunk: return "Full Dunk"
        }
    }
}

import Foundation

struct SeasonStanding: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let displayName: String
    let season: Int
    let leagueName: String
    let totalPoints: Int
    let weeklyWins: Int
    let rank: Int
    let totalPlayers: Int
    let bestWeek: Int?
    let bestWeekRecord: String?

    var isChampion: Bool { rank == 1 }
    var isPodium: Bool { rank <= 3 }

    var rankEmoji: String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "🏈"
        }
    }

    var placementText: String {
        let suffix: String
        switch rank {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
        return "\(rank)\(suffix) of \(totalPlayers)"
    }
}

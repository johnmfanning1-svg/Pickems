import Foundation

struct WeeklyResult: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let displayName: String
    let week: Int
    let season: Int
    let leagueName: String
    let correctPicks: Int
    let totalPicks: Int
    let rank: Int
    let totalPlayers: Int
    let tiebreakerDelta: Int?
    let isWeeklyWinner: Bool

    var recordText: String {
        "\(correctPicks)/\(totalPicks)"
    }

    var rankText: String {
        ordinal(rank)
    }

    var placementText: String {
        "\(rankText) of \(totalPlayers)"
    }

    private func ordinal(_ value: Int) -> String {
        let suffix: String
        let ones = value % 10
        let tens = (value / 10) % 10

        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }

        return "\(value)\(suffix)"
    }
}

import ActivityKit
import Foundation

struct PickemsLiveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var weeklyWins: Int
        var weeklyLosses: Int
        var rank: Int
        var totalPlayers: Int
        var nextGameLabel: String
        var updatedAt: Date
    }

    var groupName: String
    var weekNumber: Int
    var userDisplayName: String
}

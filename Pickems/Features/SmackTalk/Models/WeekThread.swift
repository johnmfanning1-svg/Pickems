import Foundation

/// Identifies a league's smack-talk thread for a specific week.
struct WeekThread: Identifiable, Codable, Equatable, Hashable {
    let leagueId: String
    let leagueName: String
    let season: Int
    let week: Int

    var id: String {
        "\(leagueId)-\(season)-\(week)"
    }

    var title: String {
        "Week \(week) Smack Talk"
    }

    var subtitle: String {
        "\(leagueName) • \(season)"
    }
}

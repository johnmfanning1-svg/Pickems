import Foundation

/// Map your app's standings models into sharing payloads.
enum SharingIntegration {
    static func weeklySource(
        userId: String,
        displayName: String,
        week: Int,
        season: Int,
        leagueName: String,
        correctPicks: Int,
        totalPicks: Int,
        rank: Int,
        totalPlayers: Int,
        tiebreakerDelta: Int? = nil,
        isWeeklyWinner: Bool = false
    ) -> ShareSource {
        .weekly(
            WeeklyResult(
                id: "weekly-\(season)-\(week)-\(userId)",
                userId: userId,
                displayName: displayName,
                week: week,
                season: season,
                leagueName: leagueName,
                correctPicks: correctPicks,
                totalPicks: totalPicks,
                rank: rank,
                totalPlayers: totalPlayers,
                tiebreakerDelta: tiebreakerDelta,
                isWeeklyWinner: isWeeklyWinner
            )
        )
    }

    static func seasonSource(
        userId: String,
        displayName: String,
        season: Int,
        leagueName: String,
        totalPoints: Int,
        weeklyWins: Int,
        rank: Int,
        totalPlayers: Int,
        bestWeek: Int? = nil,
        bestWeekRecord: String? = nil
    ) -> ShareSource {
        .season(
            SeasonStanding(
                id: "season-\(season)-\(userId)",
                userId: userId,
                displayName: displayName,
                season: season,
                leagueName: leagueName,
                totalPoints: totalPoints,
                weeklyWins: weeklyWins,
                rank: rank,
                totalPlayers: totalPlayers,
                bestWeek: bestWeek,
                bestWeekRecord: bestWeekRecord
            )
        )
    }
}

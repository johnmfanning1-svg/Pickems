import Foundation

enum DemoData {
    static let weeklyResult = WeeklyResult(
        id: "demo-weekly",
        userId: "user-1",
        displayName: "JMF",
        week: 7,
        season: 2025,
        leagueName: "Fannypack",
        correctPicks: 8,
        totalPicks: 10,
        rank: 2,
        totalPlayers: 12,
        tiebreakerDelta: 3,
        isWeeklyWinner: false
    )

    static let seasonStanding = SeasonStanding(
        id: "demo-season",
        userId: "user-1",
        displayName: "JMF",
        season: 2025,
        leagueName: "Fannypack",
        totalPoints: 87,
        weeklyWins: 4,
        rank: 2,
        totalPlayers: 12,
        bestWeek: 5,
        bestWeekRecord: "9/10"
    )
}

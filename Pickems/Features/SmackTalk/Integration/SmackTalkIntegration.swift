import Foundation

enum SmackTalkIntegration {
    static func context(
        userId: String,
        displayName: String,
        leagueId: String,
        leagueName: String,
        season: Int,
        week: Int
    ) -> SmackTalkContext {
        SmackTalkContext(
            userId: userId,
            displayName: displayName,
            thread: WeekThread(
                leagueId: leagueId,
                leagueName: leagueName,
                season: season,
                week: week
            )
        )
    }

    static func thread(
        leagueId: String,
        leagueName: String,
        season: Int,
        week: Int
    ) -> WeekThread {
        WeekThread(
            leagueId: leagueId,
            leagueName: leagueName,
            season: season,
            week: week
        )
    }

    /// Post a standings update into the week's smack-talk thread.
    static func systemMessage(for result: WeeklyResult) -> String {
        SmackTalkTextBuilder.systemMessage(for: result)
    }
}

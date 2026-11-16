import Foundation

enum SeasonLedgerPrivacy {
    static func hiddenGameIds(week: WeekSummary, games: [SlateGame]) -> Set<String> {
        guard week.isRollingLock, !WeekTransition.pickemsAreFullyPublic(week) else { return [] }
        return Set(
            games
                .filter { !WeekTransition.isGameLocked($0, week: week) }
                .map(\.id)
        )
    }

    /// Whether another member's pick may be shown for this game (viewer may always see own picks).
    static func mayShowPick(
        gameId: String,
        memberId: String,
        viewerId: String?,
        hiddenGameIds: Set<String>
    ) -> Bool {
        if memberId == viewerId { return true }
        return !hiddenGameIds.contains(gameId)
    }
}
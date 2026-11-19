import Foundation

/// Reopen Selections confirm copy and write target for commissioner Settings.
enum ReopenSelectionsPrompt {
    static let title = "Reopen Selections?"
    static let message =
        "Members can add and remove Selections again. Pickems close until you open the week."
    static let confirmTitle = "Reopen Selections"

    static let weekUnavailableMessage =
        "Selections can't be reopened for this week right now."

    static let leagueUnavailableMessage =
        "That league isn't available right now. Pull to refresh and try again."

    /// Frozen at tap from the pinned settings league, not `selectedGroup`.
    static func writeTarget(settingsGroupId: String, week: WeekSummary) -> (groupId: String, weekId: String)? {
        guard WeekTransition.canReopenSelections(week) else { return nil }
        return (settingsGroupId, week.id)
    }
}
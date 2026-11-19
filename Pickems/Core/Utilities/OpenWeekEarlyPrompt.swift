import Foundation

/// Commissioner lock-Selections / open-Pickems confirm copy for Settings → This Week.
enum OpenWeekEarlyPrompt {
    static let earlyButtonTitle = "Lock Selections Early, Start Pickems"

    static let earlyConfirmTitle = "Lock Selections Early, Start Pickems?"
    static let earlyConfirmMessage =
        "Members can no longer add or remove Selections. Pickems open for the games on the slate now."
    static let earlyAccessibilityLabel = "Lock Selections Early, Start Pickems"

    static func openWithGamesButtonTitle(uniqueGames: Int) -> String {
        let suffix = uniqueGames == 1 ? "" : "s"
        return "Open With \(uniqueGames) Game\(suffix)"
    }

    static func openWithGamesConfirmTitle(uniqueGames: Int) -> String {
        "Open With \(uniqueGames) Game\(uniqueGames == 1 ? "" : "s")?"
    }

    static let openWithGamesConfirmMessage =
        "Members can no longer add or remove Selections. Pickems open for the games on the slate now."

    static func openWithGamesAccessibilityLabel(uniqueGames: Int) -> String {
        openWithGamesButtonTitle(uniqueGames: uniqueGames)
    }
}
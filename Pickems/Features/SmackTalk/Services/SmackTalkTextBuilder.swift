import Foundation

enum SmackTalkTextBuilder {
    static let maxMessageLength = 280

    static func quickReplies(for result: WeeklyResult) -> [String] {
        [
            "Week \(result.week) belongs to me. Tell your friends. 📣",
            "So close to #1 you can smell it.",
            "Still ahead of half this league. That's a you problem.",
            "My picks aged like fine wine. Yours didn't.",
            "See you at the bottom of the standings.",
            "Bold strategy, Cotton. Let's see if it pays off."
        ]
    }

    static func systemMessage(for result: WeeklyResult) -> String {
        if result.isWeeklyWinner {
            return "🏆 \(result.displayName) took Week \(result.week) with \(result.recordText)."
        }
        return "📊 \(result.displayName) finished \(result.placementText) in Week \(result.week) (\(result.recordText))."
    }

    static func weekOpenMessage(for thread: WeekThread) -> String {
        "Week \(thread.week) smack talk is open. Talk your picks."
    }
}

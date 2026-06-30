import Foundation

enum SmackTalkDemoData {
    static let leagueId = "fannypack"
    static let leagueName = "Fannypack"
    static let season = 2025
    static let currentWeek = 7
    static let currentUserId = "user-1"
    static let currentDisplayName = "JMF"

    static var currentContext: SmackTalkContext {
        SmackTalkIntegration.context(
            userId: currentUserId,
            displayName: currentDisplayName,
            leagueId: leagueId,
            leagueName: leagueName,
            season: season,
            week: currentWeek
        )
    }

    static func seedMessages(for thread: WeekThread) -> [SmackTalkMessage] {
        let base = Date().addingTimeInterval(-1800)
        let members: [(id: String, name: String, text: String, offset: TimeInterval)] = [
            ("user-2", "Drew", "Georgia -3.5 was free money and you still missed it.", 60),
            ("user-3", "Tyler", "My tiebreaker is going to haunt your group chat all week.", 120),
            ("user-4", "Sam", "Bold picks only. That's why I'm sitting at 8/10.", 180),
            ("user-5", "Chris", "See everyone Saturday when the bottom half starts making excuses.", 240)
        ]

        return members.map { member in
            SmackTalkMessage(
                id: "seed-\(thread.id)-\(member.id)",
                threadId: thread.id,
                userId: member.id,
                displayName: member.name,
                text: member.text,
                createdAt: base.addingTimeInterval(member.offset),
                kind: .user
            )
        }
    }
}

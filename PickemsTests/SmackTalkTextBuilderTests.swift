import XCTest
@testable import Pickems

final class SmackTalkTextBuilderTests: XCTestCase {
    func testQuickRepliesIncludeCurrentWeek() {
        let replies = SmackTalkTextBuilder.quickReplies(for: DemoData.weeklyResult)
        XCTAssertFalse(replies.isEmpty)
        XCTAssertTrue(replies.contains(where: { $0.contains("Week 7") }))
    }

    func testSystemMessageForWeeklyWinner() {
        let winner = WeeklyResult(
            id: "winner",
            userId: "u1",
            displayName: "Ace",
            week: 7,
            season: 2025,
            leagueName: "Fannypack",
            correctPicks: 10,
            totalPicks: 10,
            rank: 1,
            totalPlayers: 12,
            tiebreakerDelta: nil,
            isWeeklyWinner: true
        )

        let message = SmackTalkTextBuilder.systemMessage(for: winner)
        XCTAssertTrue(message.contains("Ace"))
        XCTAssertTrue(message.contains("10/10"))
        XCTAssertTrue(message.contains("🏆"))
    }

    func testSystemMessageForNonWinner() {
        let message = SmackTalkTextBuilder.systemMessage(for: DemoData.weeklyResult)
        XCTAssertTrue(message.contains("JMF"))
        XCTAssertTrue(message.contains("2nd of 12"))
        XCTAssertTrue(message.contains("8/10"))
    }

    func testWeekOpenMessageUsesThreadWeek() {
        let thread = SmackTalkIntegration.thread(
            leagueId: "fannypack",
            leagueName: "Fannypack",
            season: 2025,
            week: 8
        )

        let message = SmackTalkTextBuilder.weekOpenMessage(for: thread)
        XCTAssertTrue(message.contains("Week 8"))
    }

    func testThreadIdIsStablePerWeek() {
        let weekSix = SmackTalkIntegration.thread(
            leagueId: "fannypack",
            leagueName: "Fannypack",
            season: 2025,
            week: 6
        )
        let weekSeven = SmackTalkIntegration.thread(
            leagueId: "fannypack",
            leagueName: "Fannypack",
            season: 2025,
            week: 7
        )

        XCTAssertNotEqual(weekSix.id, weekSeven.id)
        XCTAssertEqual(weekSix.id, "fannypack-2025-6")
    }
}

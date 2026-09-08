import XCTest
@testable import Pickems

final class ShareTextBuilderTests: XCTestCase {
    func testWeeklyTweetIncludesPromoAndHashtags() {
        let result = ShareableResult(weekly: DemoData.weeklyResult, tone: .fullDunk)
        let tweet = result.tweetText

        XCTAssertTrue(tweet.contains("Week 7: 8–2"))
        XCTAssertTrue(tweet.contains("Fannypack"))
        XCTAssertTrue(tweet.contains(AppConfig.appStoreURL))
        XCTAssertFalse(tweet.contains("pickems-fb.web.app"))
        XCTAssertTrue(tweet.contains(AppConfig.appHashtag))
        XCTAssertTrue(tweet.contains(AppConfig.cfbHashtag))
    }

    func testWeeklyStatsUseWinLossNotADateLikeFraction() {
        let result = ShareableResult(weekly: DemoData.weeklyResult)
        XCTAssertEqual(result.heroText, "8–2")
        XCTAssertFalse(result.statsLine.contains("/"))
        XCTAssertFalse(result.messageText.contains("correct"))
    }

    func testSeasonChampionUsesDunkToneByDefault() {
        let champion = SeasonStanding(
            id: "champ",
            userId: "u1",
            displayName: "Ace",
            season: 2025,
            leagueName: "Fannypack",
            totalPoints: 100,
            weeklyWins: 6,
            rank: 1,
            totalPlayers: 12,
            bestWeek: 3,
            bestWeekRecord: "10/10"
        )

        let result = ShareableResult(season: champion, tone: .auto)
        XCTAssertTrue(result.bragLine.localizedCaseInsensitiveContains("crown"))
        XCTAssertEqual(result.heroText, "#1")
    }

    func testWeeklyMessageOmitsLinksAndHashtags() {
        let result = ShareableResult(weekly: DemoData.weeklyResult, tone: .fullDunk)
        let message = result.messageText

        XCTAssertTrue(message.contains("Week 7: 8–2"))
        XCTAssertFalse(message.contains("http"))
        XCTAssertFalse(message.contains(AppConfig.appHashtag))
        XCTAssertFalse(message.contains("pickems-fb.web.app"))
    }

    func testWinningWeekAutoToneUsesFire() {
        let result = ShareableResult(weekly: DemoData.weeklyResult, tone: .auto)
        XCTAssertTrue(result.bragLine.contains("Not for long"))
        XCTAssertEqual(result.heroText, "8–2")
    }

    func testLosingWeekAutoToneStaysChill() {
        let losing = WeeklyResult(
            id: "poor",
            userId: "u1",
            displayName: "JMF",
            week: 1,
            season: 2026,
            leagueName: "Core 4 OG",
            correctPicks: 4,
            totalPicks: 11,
            rank: 2,
            totalPlayers: 4,
            tiebreakerDelta: nil,
            isWeeklyWinner: false
        )
        let result = ShareableResult(weekly: losing, tone: .auto)
        XCTAssertTrue(result.bragLine.contains("in the books"))
        XCTAssertFalse(result.bragLine.localizedCaseInsensitiveContains("not even close"))
        XCTAssertEqual(result.heroText, "4–7")
    }

    func testAppInviteIncludesStoreLink() {
        let message = AppShareContent.inviteMessage(leagueName: "Fannypack")
        XCTAssertTrue(message.contains("Fannypack"))
        XCTAssertTrue(message.contains(AppConfig.appStoreURL))
    }

    func testAppInviteTweetIncludesPromoAndHashtags() {
        let tweet = AppShareContent.inviteTweet(leagueName: "Fannypack")
        XCTAssertTrue(tweet.contains(AppConfig.appPromoURL))
        XCTAssertTrue(tweet.contains(AppConfig.appHashtag))
    }

    func testSMSURLBuilds() {
        let url = MessageURLBuilder.smsURL(body: "Join Pickems")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "sms")
    }

    func testXIntentURLBuilds() {
        let url = XURLBuilder.intentTweetURL(text: "Hello Pickems")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "twitter.com")
        XCTAssertTrue(url?.absoluteString.contains("intent/tweet") == true)
    }
}

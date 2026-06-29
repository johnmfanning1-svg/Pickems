import XCTest
@testable import Pickems

final class ShareTextBuilderTests: XCTestCase {
    func testWeeklyTweetIncludesPromoAndHashtags() {
        let result = ShareableResult(weekly: DemoData.weeklyResult, tone: .fullDunk)
        let tweet = result.tweetText

        XCTAssertTrue(tweet.contains("Week 7 Pickems"))
        XCTAssertTrue(tweet.contains("Fannypack"))
        XCTAssertTrue(tweet.contains(AppConfig.appPromoURL))
        XCTAssertTrue(tweet.contains(AppConfig.appHashtag))
        XCTAssertTrue(tweet.contains(AppConfig.cfbHashtag))
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
        XCTAssertTrue(result.bragLine.contains("CROWN"))
    }

    func testWeeklyMessageOmitsHashtags() {
        let result = ShareableResult(weekly: DemoData.weeklyResult, tone: .fullDunk)
        let message = result.messageText

        XCTAssertTrue(message.contains("Week 7 Pickems"))
        XCTAssertTrue(message.contains(AppConfig.appPromoURL))
        XCTAssertFalse(message.contains(AppConfig.appHashtag))
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

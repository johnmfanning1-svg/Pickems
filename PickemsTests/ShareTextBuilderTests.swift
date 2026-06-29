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

    func testXIntentURLBuilds() {
        let url = XURLBuilder.intentTweetURL(text: "Hello Pickems")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "twitter.com")
        XCTAssertTrue(url?.absoluteString.contains("intent/tweet") == true)
    }
}

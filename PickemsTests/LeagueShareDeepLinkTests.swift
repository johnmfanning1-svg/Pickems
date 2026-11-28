import XCTest
@testable import Pickems

final class LeagueShareDeepLinkTests: XCTestCase {
    func testParseShortLeaguePathOnWebHost() {
        let url = URL(string: "https://pickems-fb.web.app/l/group-abc")!
        XCTAssertEqual(DeepLinkRouter.parse(url: url), .openLeagues(groupId: "group-abc"))
    }

    func testParseLeagueSlugOnWebHost() {
        let url = URL(string: "https://pickems-fb.web.app/league/group-xyz")!
        XCTAssertEqual(DeepLinkRouter.parse(url: url), .openLeagues(groupId: "group-xyz"))
    }

    func testParseLeagueSlugRejectsWeekPaths() {
        let url = URL(string: "https://pickems-fb.web.app/league/group-1/week/2026-W6/pickems")!
        XCTAssertEqual(DeepLinkRouter.parse(url: url), .openWeekPickems(groupId: "group-1", weekId: "2026-W6"))
    }

    func testParseCustomSchemeShortHost() {
        let url = URL(string: "pickems://l/group-99")!
        XCTAssertEqual(DeepLinkRouter.parse(url: url), .openLeagues(groupId: "group-99"))
    }

    func testParsePickemsSchemeLeagueOnly() {
        let url = URL(string: "pickems://league/group-only")!
        XCTAssertEqual(DeepLinkRouter.parse(url: url), .openLeagues(groupId: "group-only"))
    }

    func testParseSharedLeagueLinkHelper() {
        XCTAssertEqual(
            DeepLinkRouter.parseSharedLeagueLink(path: "l/abc 123"),
            .openLeagues(groupId: "abc 123")
        )
        XCTAssertNil(DeepLinkRouter.parseSharedLeagueLink(path: "l/a/b"))
        XCTAssertNil(DeepLinkRouter.parseSharedLeagueLink(path: "join/abc"))
    }

    func testLeagueShareURLUsesHostedPath() {
        XCTAssertEqual(
            AppConfig.leagueShareURL(groupId: "my-league"),
            "https://pickems-fb.web.app/l/my-league"
        )
    }

    func testScreenShareCaptionIncludesLeagueURL() {
        let caption = ScreenShareTextBuilder.caption(
            leagueName: "Friends",
            contextLine: "Season leaderboard",
            groupId: "g-1"
        )
        XCTAssertTrue(caption.contains(AppConfig.leagueShareURL(groupId: "g-1")))
        XCTAssertTrue(caption.contains(AppConfig.appStoreURL))
    }
}
import XCTest
@testable import Pickems

@MainActor
final class ShareCardRendererTests: XCTestCase {
    func testRendersLeaderboardCardImage() {
        let model = LeaderboardShareModel(
            groupId: "g1",
            leagueName: "Test League",
            periodLabel: "This Week",
            rows: [
                ShareLeaderboardRow(
                    rank: 1,
                    displayName: "Ace",
                    avatarColorHex: "#112233",
                    wins: 8,
                    losses: 2,
                    caption: "Even",
                    isViewer: true
                ),
            ],
            omittedCount: 0
        )
        let content = ScreenShareContent.leaderboard(model)
        let image = ShareCardRenderer.renderScreenCard(content)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }

    func testRendersSeasonLedgerCardImage() {
        let model = SeasonLedgerShareModel(
            groupId: "g1",
            leagueName: "Ledger League",
            columns: [ShareLedgerMemberColumn(shortName: "You", isViewer: true)],
            weeks: [ShareLedgerWeekRow(title: "Week 1", records: [ShareLedgerWLPair(wins: 2, losses: 1)])],
            seasonTotals: [ShareLedgerWLPair(wins: 2, losses: 1)],
            gamesBack: ["—"],
            omittedMemberCount: 0
        )
        let image = ShareCardRenderer.renderScreenCard(.seasonLedger(model))
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }

    func testRendersPickemsChartCardImage() {
        let model = PickemsChartShareModel(
            groupId: "g1",
            leagueName: "Chart League",
            periodLabel: "Week 2",
            columns: [
                ShareChartMemberColumn(shortName: "You", isViewer: true),
                ShareChartMemberColumn(shortName: "Ace", isViewer: false),
            ],
            games: [
                ShareChartGameRow(
                    matchup: "AWY @ HOM",
                    scoreLine: "17–21",
                    cells: [
                        ShareChartCell(kind: .pick("HOM", .won)),
                        ShareChartCell(kind: .pick("AWY", .lost)),
                    ]
                ),
            ],
            omittedMemberCount: 0,
            omittedGameCount: 0,
            pickMode: .ats,
            showsSpreads: false
        )
        let image = ShareCardRenderer.renderScreenCard(.pickemsChart(model))
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }
}
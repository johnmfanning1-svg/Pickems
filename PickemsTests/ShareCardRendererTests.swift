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
            omittedMemberCount: 0,
            memberColumnWidth: 72,
            weekColumnWidth: 120
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
                    matchup: "AWY @ HOM  17–21",
                    scoreLine: nil,
                    cells: [
                        ShareChartCell(kind: .pick("HOM", .won)),
                        ShareChartCell(kind: .pick("AWY", .lost)),
                    ]
                ),
            ],
            stillToPlay: ShareStillToPlayStrip(chips: ["UK", "MICH"], picksHiddenNote: "Picks hidden until kickoff"),
            omittedMemberCount: 0,
            omittedGameCount: 0,
            pickMode: .ats,
            showsSpreads: false,
            gameColumnWidth: 164,
            memberColumnWidth: 72
        )
        let image = ShareCardRenderer.renderScreenCard(.pickemsChart(model))
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }

    func testExportDarkPickemsChartSamplePNG() throws {
        let members = (1 ... 11).map { index in
            GroupMember(
                id: "m\(index)",
                displayName: "Player \(index)",
                avatarColorHex: "#223344",
                role: .member,
                joinedAt: Date(),
                seasonWins: 12 - index,
                seasonLosses: index
            )
        }
        var games: [SlateGame] = []
        for index in 1 ... 8 {
            let status: SlateGame.GameStatus = index <= 5 ? .final : .scheduled
            games.append(
                SlateGame(
                    id: "g\(index)",
                    espnEventId: "g\(index)",
                    homeTeamId: "home\(index)",
                    homeTeamName: "Home",
                    homeTeamAbbreviation: "H\(index)",
                    homeTeamLogoURL: nil,
                    awayTeamId: "away\(index)",
                    awayTeamName: "Away",
                    awayTeamAbbreviation: "A\(index)",
                    awayTeamLogoURL: nil,
                    spread: 3,
                    spreadTeamId: "home\(index)",
                    kickoff: Date(),
                    status: status,
                    homeScore: 24,
                    awayScore: 17,
                    winnerTeamId: "home\(index)"
                )
            )
        }

        var picks: [String: UserPick] = [:]
        for member in members {
            var memberPicks: [String: String] = [:]
            for game in games {
                memberPicks[game.id] = game.homeTeamId
            }
            picks[member.id] = UserPick(
                id: member.id,
                userId: member.id,
                displayName: member.displayName,
                picks: memberPicks,
                submittedAt: Date(),
                isLocked: true
            )
        }

        let content = ScreenShareContent.makePickemsChart(
            groupId: "sample-league",
            leagueName: "Sample League",
            periodLabel: "Week 9",
            members: members,
            games: games,
            picksByUserId: picks,
            hiddenGameIds: Set(games.filter { $0.status == .scheduled }.map(\.id)),
            pickMode: .ats,
            currentUserId: "m5",
            liveCards: [:]
        )
        XCTAssertNotNil(content)

        let defaults = AppearancePreferenceStore.appGroupDefaults
        let saved = defaults.string(forKey: AppearancePreference.storageKey)
        defaults.set(AppearancePreference.dark.rawValue, forKey: AppearancePreference.storageKey)
        defer {
            if let saved {
                defaults.set(saved, forKey: AppearancePreference.storageKey)
            } else {
                defaults.removeObject(forKey: AppearancePreference.storageKey)
            }
        }

        let image = ShareCardRenderer.renderScreenCard(content!)
        XCTAssertNotNil(image)

        let mediaDir = "/cursor/stores/bc-f97379f5-cda9-4b47-911f-f6dd44e312a6/media"
        try FileManager.default.createDirectory(atPath: mediaDir, withIntermediateDirectories: true)
        let pngURL = URL(fileURLWithPath: "\(mediaDir)/share-pickems-card-sample-dark.png")
        if let data = image?.pngData() {
            try data.write(to: pngURL, options: .atomic)
            XCTAssertTrue(FileManager.default.fileExists(atPath: pngURL.path))
        } else {
            XCTFail("Expected PNG data")
        }
    }
}
import XCTest
@testable import Pickems

final class ShareCardLayoutTests: XCTestCase {
    func testLeaderboardShowsTopEight() {
        let entries = (1 ... 12).map { standing(rank: $0, id: "u\($0)", name: "Player\($0)") }
        let layout = ShareCardLayout.leaderboard(
            entries: entries,
            scope: .season,
            viewerId: "u1",
            leaderWins: 12
        )
        XCTAssertEqual(layout.rows.count, 8)
        XCTAssertEqual(layout.rows.first?.rank, 1)
        XCTAssertEqual(layout.rows.last?.rank, 8)
    }

    func testLeaderboardIncludesViewerWhenOutsideTopEight() {
        let entries = (1 ... 12).map { standing(rank: $0, id: "u\($0)", name: "Player\($0)") }
        let layout = ShareCardLayout.leaderboard(
            entries: entries,
            scope: .season,
            viewerId: "u12",
            leaderWins: 12
        )
        XCTAssertTrue(layout.rows.contains(where: { $0.rank == 12 && $0.isViewer }))
        XCTAssertEqual(layout.rows.count, 8)
    }

    func testLeaderboardPreservesTrueRanks() {
        let entries = [
            standing(rank: 1, id: "a", name: "Ace"),
            standing(rank: 15, id: "me", name: "Me"),
        ]
        let layout = ShareCardLayout.leaderboard(entries: entries, scope: .season, viewerId: "me", leaderWins: 10)
        XCTAssertEqual(Set(layout.rows.map(\.rank)), Set([1, 15]))
    }

    func testLeaderboardOmittedCount() {
        let entries = (1 ... 20).map { standing(rank: $0, id: "u\($0)", name: "P\($0)") }
        let layout = ShareCardLayout.leaderboard(entries: entries, scope: .thisWeek, viewerId: "u1", leaderWins: 20)
        XCTAssertEqual(layout.omittedCount, 12)
    }

    func testLeaderboardNoOmittedWhenEveryoneFits() {
        let entries = (1 ... 5).map { standing(rank: $0, id: "u\($0)", name: "P\($0)") }
        let layout = ShareCardLayout.leaderboard(entries: entries, scope: .season, viewerId: "u1", leaderWins: 5)
        XCTAssertEqual(layout.omittedCount, 0)
    }

    func testLeaderboardSingleMemberLeague() {
        let entries = [standing(rank: 1, id: "solo", name: "Solo")]
        let layout = ShareCardLayout.leaderboard(entries: entries, scope: .season, viewerId: "solo", leaderWins: 3)
        XCTAssertEqual(layout.rows.count, 1)
        XCTAssertEqual(layout.omittedCount, 0)
    }

    func testLeaderboardPeriodLabels() {
        XCTAssertEqual(ShareCardLayout.leaderboardPeriodLabel(scope: .thisWeek), "This Week")
        XCTAssertEqual(ShareCardLayout.leaderboardPeriodLabel(scope: .season), "Season")
        XCTAssertEqual(
            ShareCardLayout.leaderboardPeriodLabel(scope: .bowl),
            CFBBowlSeason.userFacingBowlWeekName
        )
        XCTAssertFalse(ShareCardLayout.leaderboardPeriodLabel(scope: .bowl).localizedCaseInsensitiveContains("Mode"))
    }

    func testShareCardTableSpansFullContentWidth() {
        let inner = ShareCardLayout.chartInnerWidth
        for memberCount in [1, 4, 12] {
            let members = (1 ... memberCount).map { member(id: "m\($0)", name: "M\($0)", wins: $0) }
            let games = [slateGame(id: "g1")]
            let chart = ShareCardLayout.pickemsChart(
                members: members,
                games: games,
                picksByUserId: [:],
                hiddenGameIds: [],
                pickMode: .ats,
                currentUserId: "m1",
                liveCards: [:]
            )
            let pickemsWidth = ShareCardLayout.tableContentWidth(
                leadWidth: chart.metrics.leadColumnWidth,
                memberWidth: chart.metrics.memberColumnWidth,
                memberCount: chart.columns.count
            )
            XCTAssertEqual(pickemsWidth, inner, accuracy: 0.5, "pickems chart memberCount=\(memberCount)")
            if memberCount <= 4 {
                XCTAssertLessThanOrEqual(chart.metrics.memberColumnWidth, ShareCardLayout.maxMemberColumnWidth + 0.01)
            }

            let data = ledgerData(memberIds: members.map(\.id))
            let ledger = ShareCardLayout.seasonLedger(data: data, members: members, currentUserId: "m1")
            let ledgerWidth = ShareCardLayout.tableContentWidth(
                leadWidth: ledger.weekColumnWidth,
                memberWidth: ledger.memberColumnWidth,
                memberCount: ledger.columns.count
            )
            XCTAssertEqual(ledgerWidth, inner, accuracy: 0.5, "season ledger memberCount=\(memberCount)")
        }
        let maxSlots = ShareCardLayout.maxMemberColumnSlots()
        XCTAssertGreaterThanOrEqual(maxSlots, 10)
    }

    func testMembersForShareColumnsViewerFirstAndNearestStandings() {
        let members = (1 ... 12).map { member(id: "m\($0)", name: "M\($0)", wins: $0) }
        let picked = ShareCardLayout.membersForShareColumns(
            members: members,
            currentUserId: "m6",
            limit: 5
        )
        XCTAssertEqual(picked.map(\.id), ["m6", "m7", "m5", "m8", "m4"])
    }

    func testLedgerKeepsViewerColumn() {
        let members = [
            member(id: "a", name: "Alpha", wins: 10),
            member(id: "b", name: "Bravo", wins: 9),
            member(id: "me", name: "Viewer", wins: 2),
        ]
        let data = ledgerData(memberIds: ["a", "b", "me"])
        let layout = ShareCardLayout.seasonLedger(data: data, members: members, currentUserId: "me")
        XCTAssertTrue(layout.columns.contains(where: { $0.isViewer }))
        XCTAssertEqual(layout.columns.first?.shortName, "You")
    }

    func testLedgerTrimsMembersWithOmittedCount() {
        let members = (1 ... 15).map { member(id: "m\($0)", name: "M\($0)", wins: 20 - $0) }
        let data = ledgerData(memberIds: members.map(\.id))
        let layout = ShareCardLayout.seasonLedger(data: data, members: members, currentUserId: "m15")
        let slotCap = ShareCardLayout.maxMemberColumnSlots(minimumLeadWidth: ShareCardLayout.ledgerWeekColumnWidth)
        XCTAssertEqual(layout.columns.count, slotCap)
        XCTAssertEqual(layout.omittedMemberCount, 15 - slotCap)
    }

    func testLedgerWeekTitles() {
        let bowlWeek = week(id: "bowl-bonanza-1", number: 99)
        let armyWeek = week(id: "army-navy-classic", number: 15)
        let regular = week(id: "w7", number: 7)
        XCTAssertEqual(SeasonLedgerWeekTitle.rowTitle(for: bowlWeek), "Bowl Bonanza")
        XCTAssertEqual(SeasonLedgerWeekTitle.rowTitle(for: armyWeek), "Army Navy")
        XCTAssertEqual(SeasonLedgerWeekTitle.rowTitle(for: regular), "Week 7")
    }

    func testLedgerSeasonTotals() {
        let members = [member(id: "a", name: "Alpha", wins: 0)]
        let week = ledgerWeekBoard(week: week(id: "w1", number: 1), winsByMember: ["a": (2, 1)])
        let data = SeasonLedgerSeasonData(groupId: "g1", weeks: [week], memberIds: ["a"])
        let layout = ShareCardLayout.seasonLedger(data: data, members: members, currentUserId: "a")
        XCTAssertEqual(layout.seasonTotals.first?.wins, 2)
        XCTAssertEqual(layout.seasonTotals.first?.losses, 1)
    }

    func testChartIncludesViewerColumn() {
        let members = [
            member(id: "a", name: "Alpha", wins: 4),
            member(id: "me", name: "Viewer", wins: 1),
        ]
        let games = [slateGame(id: "g1"), slateGame(id: "g2")]
        let picks: [String: UserPick] = [
            "a": userPick(userId: "a", picks: ["g1": "home"]),
            "me": userPick(userId: "me", picks: ["g1": "away"]),
        ]
        let layout = ShareCardLayout.pickemsChart(
            members: members,
            games: games,
            picksByUserId: picks,
            hiddenGameIds: [],
            pickMode: .ats,
            currentUserId: "me",
            liveCards: [:]
        )
        XCTAssertTrue(layout.columns.contains(where: { $0.isViewer }))
    }

    func testChartTrimsMembersUsingWidthCap() {
        let members = (1 ... 12).map { member(id: "m\($0)", name: "M\($0)", wins: $0) }
        let games = [slateGame(id: "g1")]
        let layout = ShareCardLayout.pickemsChart(
            members: members,
            games: games,
            picksByUserId: [:],
            hiddenGameIds: [],
            pickMode: .ats,
            currentUserId: "m12",
            liveCards: [:]
        )
        XCTAssertEqual(layout.columns.count, layout.metrics.maxMemberColumnSlots)
        XCTAssertEqual(layout.omittedMemberCount, 12 - layout.metrics.maxMemberColumnSlots)
        XCTAssertEqual(layout.columns.first?.shortName, "You")
    }

    func testChartDoesNotExposeHiddenRollingLockPickForOthers() {
        let members = [
            member(id: "a", name: "Alpha", wins: 1),
            member(id: "me", name: "Viewer", wins: 1),
        ]
        let game = slateGame(id: "g-hidden")
        let picks: [String: UserPick] = [
            "a": userPick(userId: "a", picks: ["g-hidden": "home"]),
            "me": userPick(userId: "me", picks: ["g-hidden": "away"]),
        ]
        let layout = ShareCardLayout.pickemsChart(
            members: members,
            games: [game],
            picksByUserId: picks,
            hiddenGameIds: ["g-hidden"],
            pickMode: .ats,
            currentUserId: "me",
            liveCards: [:]
        )
        let viewerCell = layout.games.first?.cells[0]
        let otherCell = layout.games.first?.cells[1]
        if case .locked = otherCell?.kind {
            // expected
        } else {
            XCTFail("Other member pick should be locked")
        }
        if case .pick(let abbrev, _) = viewerCell?.kind {
            XCTAssertEqual(abbrev, "AWY")
        } else {
            XCTFail("Viewer pick should remain visible")
        }
    }

    func testChartKeepsScheduledGamesInStillToPlayStrip() {
        let members = [member(id: "me", name: "Viewer", wins: 2)]
        let finalGame = slateGame(id: "g-final", status: .final, kickoff: Date(timeIntervalSince1970: 100))
        let scheduled = slateGame(id: "g-later", status: .scheduled, kickoff: Date(timeIntervalSince1970: 200))
        let picks: [String: UserPick] = [
            "me": userPick(userId: "me", picks: [
                "g-final": "home",
                "g-later": "away",
            ]),
        ]
        let layout = ShareCardLayout.pickemsChart(
            members: members,
            games: [scheduled, finalGame],
            picksByUserId: picks,
            hiddenGameIds: ["g-later"],
            pickMode: .ats,
            currentUserId: "me",
            liveCards: [:]
        )
        XCTAssertEqual(layout.games.count, 1)
        XCTAssertEqual(layout.games.first?.matchup, "AWY @ HOM  17–21")
        XCTAssertEqual(layout.stillToPlay?.chips, ["AWY"])
        XCTAssertEqual(layout.stillToPlay?.picksHiddenNote, "Picks hidden until kickoff")
    }

    func testCaptionContainsAppStoreURL() {
        let content = ScreenShareContent.makeLeaderboard(
            groupId: "core-4",
            leagueName: "Core 4",
            scope: .bowl,
            entries: [standing(rank: 1, id: "a", name: "Ace")],
            viewerId: "a",
            leaderWins: 4
        )
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.caption.contains(AppConfig.appStoreURL) == true)
        XCTAssertTrue(content?.caption.contains(AppConfig.leagueShareURL(groupId: "core-4")) == true)
        XCTAssertTrue(content?.caption.contains("Core 4") == true)
        XCTAssertFalse(content?.caption.contains("invite") == true)
        XCTAssertFalse(content?.caption.contains("@") == true)
    }

    func testLeagueShareURLFormatForFooter() {
        XCTAssertEqual(
            AppConfig.leagueShareURL(groupId: "abc"),
            "https://pickems-fb.web.app/l/abc"
        )
    }

    // MARK: - Fixtures

    private func standing(rank: Int, id: String, name: String) -> StandingEntry {
        StandingEntry(
            id: id,
            displayName: name,
            avatarColorHex: "#336699",
            weeklyWins: max(0, 12 - rank),
            weeklyLosses: rank - 1,
            seasonWins: max(0, 12 - rank),
            seasonLosses: rank - 1,
            rank: rank,
            isTied: false
        )
    }

    private func member(id: String, name: String, wins: Int) -> GroupMember {
        GroupMember(
            id: id,
            displayName: name,
            avatarColorHex: "#445566",
            role: .member,
            joinedAt: Date(),
            seasonWins: wins,
            seasonLosses: 0
        )
    }

    private func week(id: String, number: Int) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: 2026,
            weekNumber: number,
            status: .scored,
            slateSize: 10,
            selectionMode: .member,
            selectionsPerMember: 1,
            nominationCount: 0
        )
    }

    private func ledgerData(memberIds: [String]) -> SeasonLedgerSeasonData {
        SeasonLedgerSeasonData(
            groupId: "g1",
            weeks: [ledgerWeekBoard(week: week(id: "w1", number: 1), winsByMember: [:])],
            memberIds: memberIds
        )
    }

    private func ledgerWeekBoard(week: WeekSummary, winsByMember: [String: (Int, Int)]) -> SeasonLedgerWeekBoard {
        var records: [String: SeasonLedgerMemberRecord] = [:]
        for (memberId, wl) in winsByMember {
            records[memberId] = SeasonLedgerMemberRecord(wins: wl.0, losses: wl.1, pushes: 0)
        }
        return SeasonLedgerWeekBoard(
            week: week,
            games: [],
            picksByUserId: [:],
            hiddenGameIds: [],
            recordsByMemberId: records,
            pickMode: .ats
        )
    }

    private func slateGame(
        id: String,
        status: SlateGame.GameStatus = .final,
        kickoff: Date = Date()
    ) -> SlateGame {
        SlateGame(
            id: id,
            espnEventId: id,
            homeTeamId: "home",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "away",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            spread: 3,
            spreadTeamId: "home",
            kickoff: kickoff,
            status: status,
            homeScore: 21,
            awayScore: 17,
            winnerTeamId: "home"
        )
    }

    private func userPick(userId: String, picks: [String: String]) -> UserPick {
        UserPick(
            id: userId,
            userId: userId,
            displayName: userId,
            picks: picks,
            submittedAt: Date(),
            isLocked: true
        )
    }
}
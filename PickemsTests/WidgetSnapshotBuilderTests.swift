import Foundation
import Testing
@testable import Pickems

struct WidgetSnapshotBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func nilWeekProducesNoExtras() {
        let extras = WidgetSnapshotBuilder.extras(
            week: nil,
            games: [],
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras == .empty)
    }

    @Test func selectionWeekKeepsFutureGamesUnlocked() {
        let kickoff = now.addingTimeInterval(86_400)
        let extras = WidgetSnapshotBuilder.extras(
            week: week(status: .selection, selectionDeadline: now.addingTimeInterval(3_600), pickDeadline: kickoff),
            games: [slate(id: "1", kickoff: kickoff)],
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.selectionsDeadline == now.addingTimeInterval(3_600))
        #expect(extras.pickemsDeadline == kickoff)
        #expect(extras.games?.first?.isLocked == false)
        #expect(extras.games?.first?.isFinal == false)
    }

    @Test func pickingWeekDropsTheSelectionDeadline() {
        let extras = WidgetSnapshotBuilder.extras(
            week: week(
                status: .picking,
                selectionDeadline: now.addingTimeInterval(3_600),
                pickDeadline: now.addingTimeInterval(7_200)
            ),
            games: [],
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.selectionsDeadline == nil)
        #expect(extras.pickemsDeadline == now.addingTimeInterval(7_200))
    }

    @Test func weekZeroSkipsTheSelectionDeadline() {
        let extras = WidgetSnapshotBuilder.extras(
            week: week(
                status: .selection,
                weekNumber: 0,
                selectionDeadline: now.addingTimeInterval(3_600),
                pickDeadline: now.addingTimeInterval(7_200)
            ),
            games: [],
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.selectionsDeadline == nil)
    }

    @Test func rollingLockSkipsTheGameThatAlreadyKicked() {
        let first = now.addingTimeInterval(-60)
        let second = now.addingTimeInterval(3_600)
        let extras = WidgetSnapshotBuilder.extras(
            week: week(
                status: .picking,
                pickDeadline: first,
                pickLockMode: .rolling,
                weekLockAt: second
            ),
            games: [
                slate(id: "thu", kickoff: first, status: .inProgress, homeScore: 7, awayScore: 3),
                slate(id: "sat", kickoff: second),
            ],
            picks: ["thu": "h"],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.rollingLock == true)
        #expect(extras.nextLockAt == second)
        #expect(extras.games?.first?.isLocked == true)
        #expect(extras.games?.last?.isLocked == false)
        #expect(extras.games?.first?.result == .pending)
    }

    @Test func straightUpResults() {
        let kickoff = now.addingTimeInterval(-3_600)
        let extras = WidgetSnapshotBuilder.extras(
            week: week(status: .locked, pickDeadline: kickoff),
            games: [
                slate(id: "win", kickoff: kickoff, status: .final, homeScore: 21, awayScore: 14),
                slate(id: "loss", kickoff: kickoff, status: .final, homeScore: 10, awayScore: 17),
                slate(id: "push", kickoff: kickoff, status: .final, homeScore: 14, awayScore: 14),
                slate(id: "none", kickoff: kickoff, status: .final, homeScore: 21, awayScore: 14),
            ],
            picks: ["win": "h", "loss": "h", "push": "h"],
            pickMode: .straightUp,
            now: now
        )
        let results = Dictionary(uniqueKeysWithValues: (extras.games ?? []).map { ($0.id, $0.result) })
        #expect(results["win"] == .win)
        #expect(results["loss"] == .loss)
        #expect(results["push"] == .push)
        #expect(results["none"] == .loss)
        #expect(extras.games?.first { $0.id == "win" }?.userPick == "H")
    }

    @Test func capsAtTwelveAndKeepsALaterLiveGame() {
        var games: [SlateGame] = (0..<12).map { index in
            slate(
                id: "final-\(index)",
                kickoff: now.addingTimeInterval(TimeInterval(index * 60)),
                status: .final,
                homeScore: 10,
                awayScore: 7
            )
        }
        games.append(slate(id: "live", kickoff: now.addingTimeInterval(50_000), status: .inProgress, homeScore: 3, awayScore: 0))
        let extras = WidgetSnapshotBuilder.extras(
            week: week(status: .picking, pickDeadline: now.addingTimeInterval(-60), pickLockMode: .rolling),
            games: games,
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.games?.count == 12)
        #expect(extras.games?.contains { $0.id == "live" } == true)
    }

    @Test func carriesTheSlateForwardForTheSameLeagueAndWeekOnly() {
        let keptDeadline = now.addingTimeInterval(3_600)
        let keptLock = now.addingTimeInterval(7_200)
        let keptGame = StandingsSnapshot.SnapshotGame(
            id: "sat",
            awayShortName: "AWAY",
            homeShortName: "HOME",
            kickoff: now.addingTimeInterval(-1_800),
            isLocked: true,
            isFinal: false,
            awayScore: 7,
            homeScore: 10,
            userPick: "HOME",
            result: .pending
        )
        var previous = StandingsSnapshot(
            groupId: "league",
            groupName: "Saturday Crew",
            weekNumber: 6,
            seasonYear: 2026,
            userId: "u",
            userDisplayName: "You",
            weeklyWins: 2,
            weeklyLosses: 1,
            seasonWins: 10,
            seasonLosses: 4,
            rank: 2,
            totalPlayers: 8,
            topEntries: [],
            updatedAt: now
        )
        previous.selectionsDeadline = keptDeadline
        previous.pickemsDeadline = keptLock
        previous.games = [keptGame]
        previous.nextLockAt = keptLock

        let fresh = WidgetSnapshotBuilder.Extras(
            selectionsDeadline: now.addingTimeInterval(99),
            pickemsDeadline: now.addingTimeInterval(100),
            rollingLock: true,
            games: [],
            nextLockAt: nil
        )

        let same = WidgetSnapshotBuilder.carryForward(
            fresh,
            previous: previous,
            groupId: "league",
            weekNumber: 6
        )
        #expect(same.games == [keptGame])
        #expect(same.nextLockAt == keptLock)
        #expect(same.selectionsDeadline == keptDeadline)
        #expect(same.pickemsDeadline == keptLock)
        #expect(same.rollingLock == true)

        let otherLeague = WidgetSnapshotBuilder.carryForward(
            fresh,
            previous: previous,
            groupId: "other",
            weekNumber: 6
        )
        #expect(otherLeague == fresh)

        let otherWeek = WidgetSnapshotBuilder.carryForward(
            fresh,
            previous: previous,
            groupId: "league",
            weekNumber: 7
        )
        #expect(otherWeek == fresh)
    }

    @Test func noPicksYetCountsTheWholeSlate() {
        let extras = counts(picks: [:], lockedPast: false)
        #expect(extras.picksMade == 0)
        #expect(extras.picksTotal == 3)
    }

    @Test func partialPicksCountOnlyChosenGames() {
        let extras = counts(picks: ["1": "h"], lockedPast: false)
        #expect(extras.picksMade == 1)
        #expect(extras.picksTotal == 3)
    }

    @Test func allPicksInWhenEveryGameIsChosen() {
        let extras = counts(picks: ["1": "h", "2": "a", "3": "h"], lockedPast: false)
        #expect(extras.picksMade == 3)
        #expect(extras.picksTotal == 3)
    }

    @Test func lockedGamesStayInThePickTotal() {
        let extras = counts(picks: ["1": "h"], lockedPast: true)
        #expect(extras.games?.first?.isLocked == true)
        #expect(extras.games?.last?.isLocked == false)
        #expect(extras.picksMade == 1)
        #expect(extras.picksTotal == 3)
    }

    @Test func statusTextAndTeamColorsPassThrough() {
        let kickoff = now.addingTimeInterval(3_600)
        let extras = WidgetSnapshotBuilder.extras(
            week: week(status: .picking, pickDeadline: kickoff),
            games: [
                slate(
                    id: "osu",
                    kickoff: kickoff,
                    homeTeamId: "194",
                    homeAbbreviation: "OSU",
                    awayTeamId: "130",
                    awayAbbreviation: "MICH"
                ),
                slate(id: "final", kickoff: now.addingTimeInterval(-3_600), status: .final, homeScore: 21, awayScore: 14),
                slate(id: "mystery", kickoff: kickoff, homeTeamId: "nope", homeAbbreviation: "ZZZ", awayTeamId: "nope2", awayAbbreviation: "YYY"),
            ],
            picks: [:],
            pickMode: .straightUp,
            now: now,
            statusTextByGameId: ["osu": "Q3 4:12"]
        )
        let byId = Dictionary(uniqueKeysWithValues: (extras.games ?? []).map { ($0.id, $0) })
        #expect(byId["osu"]?.statusText == "Q3 4:12")
        #expect(byId["osu"]?.homeColorHex == "#BA0C2F")
        #expect(byId["osu"]?.awayColorHex == "#00274C")
        #expect(byId["final"]?.statusText == "Final")
        #expect(byId["mystery"]?.homeColorHex == nil)
        #expect(byId["mystery"]?.awayColorHex == nil)
    }

    @Test func selectionWeekCountsTheUsersNominationsNotTheMergedSlate() {
        let kickoff = now.addingTimeInterval(86_400)
        let extras = WidgetSnapshotBuilder.extras(
            week: week(
                status: .selection,
                selectionDeadline: now.addingTimeInterval(3_600),
                pickDeadline: kickoff,
                selectionsPerMember: 2,
                slateSize: 8
            ),
            games: [
                slate(id: "mine-1", kickoff: kickoff, homeAbbreviation: "OSU", awayAbbreviation: "PSU"),
                slate(id: "mine-2", kickoff: kickoff.addingTimeInterval(60), homeAbbreviation: "MICH", awayAbbreviation: "MSU"),
                slate(id: "them-1", kickoff: kickoff.addingTimeInterval(120), homeAbbreviation: "ALA", awayAbbreviation: "UGA"),
                slate(id: "them-2", kickoff: kickoff.addingTimeInterval(180), homeAbbreviation: "ORE", awayAbbreviation: "USC"),
            ],
            picks: [:],
            pickMode: .straightUp,
            now: now,
            nominations: [
                nomination(eventId: "mine-1", submittedBy: "me"),
                nomination(eventId: "mine-2", submittedBy: "me"),
                nomination(eventId: "them-1", submittedBy: "them"),
                nomination(eventId: "them-2", submittedBy: "them"),
            ],
            userId: "me"
        )
        #expect(extras.selectionQuota == WidgetSelectionQuota.member)
        #expect(extras.selectionsMade == 2)
        #expect(extras.selectionsTotal == 2)
        #expect(extras.picksMade == 0)
        #expect(extras.picksTotal == 4)
        let selected = (extras.games ?? []).filter { $0.isUserSelection == true }.map(\.id)
        #expect(selected == ["mine-1", "mine-2"])
        #expect((extras.games ?? []).filter { $0.isUserSelection == false }.count == 2)
        #expect((extras.games ?? []).allSatisfy { $0.userPick == nil })
    }

    @Test func selectionWeekWithNoNominationsYet() {
        let extras = WidgetSnapshotBuilder.extras(
            week: week(
                status: .selection,
                selectionDeadline: now.addingTimeInterval(3_600),
                selectionsPerMember: 2
            ),
            games: [slate(id: "them", kickoff: now.addingTimeInterval(86_400))],
            picks: [:],
            pickMode: .straightUp,
            now: now,
            nominations: [nomination(eventId: "them", submittedBy: "them")],
            userId: "me"
        )
        #expect(extras.selectionsMade == 0)
        #expect(extras.selectionsTotal == 2)
        #expect(extras.picksMade == 0)
        #expect(extras.picksTotal == 1)
        #expect(extras.games?.allSatisfy { $0.isUserSelection == false } == true)
    }

    @Test func commissionerSelectionCountsTheSlateNotAMemberQuota() {
        let extras = WidgetSnapshotBuilder.extras(
            week: week(
                status: .selection,
                selectionDeadline: now.addingTimeInterval(3_600),
                selectionMode: .commissioner,
                selectionsPerMember: 2,
                slateSize: 8
            ),
            games: [
                slate(id: "1", kickoff: now.addingTimeInterval(3_600)),
                slate(id: "2", kickoff: now.addingTimeInterval(4_000)),
                slate(id: "3", kickoff: now.addingTimeInterval(5_000)),
            ],
            picks: [:],
            pickMode: .straightUp,
            now: now,
            nominations: [
                nomination(eventId: "1", submittedBy: "commissioner"),
                nomination(eventId: "2", submittedBy: "commissioner"),
                nomination(eventId: "3", submittedBy: "commissioner"),
            ],
            userId: "member"
        )
        #expect(extras.selectionQuota == WidgetSelectionQuota.commissioner)
        #expect(extras.selectionsMade == 3)
        #expect(extras.selectionsTotal == 8)
        #expect(extras.picksMade == 0)
        #expect(extras.picksTotal == 3)
        #expect(extras.games?.allSatisfy { $0.isUserSelection == nil } == true)
    }

    @Test func pickingWeekCountsTheFullSlatePastTheWidgetCap() {
        let games = (0..<13).map { index in
            slate(id: "g-\(index)", kickoff: now.addingTimeInterval(TimeInterval(3_600 + index)))
        }
        var picks: [String: String] = [:]
        for index in 0..<5 {
            picks["g-\(index)"] = "h"
        }
        let extras = WidgetSnapshotBuilder.extras(
            week: week(status: .picking, pickDeadline: now.addingTimeInterval(3_600), slateSize: 13),
            games: games,
            picks: picks,
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.selectionQuota == nil)
        #expect(extras.selectionsMade == nil)
        #expect(extras.picksMade == 5)
        #expect(extras.picksTotal == 13)
        #expect(extras.games?.count == 12)
    }

    @Test func liveScoreOverlayFeedsPickProgress() {
        let kickoff = now.addingTimeInterval(-1_800)
        let extras = WidgetSnapshotBuilder.extras(
            week: week(status: .locked, pickDeadline: kickoff),
            games: [
                slate(id: "live", kickoff: kickoff, homeAbbreviation: "OSU", awayAbbreviation: "MICH"),
            ],
            picks: ["live": "h"],
            pickMode: .straightUp,
            now: now,
            liveScores: [
                "live": .init(awayScore: 14, homeScore: 21, status: .inProgress, statusText: "Q3 4:12"),
            ]
        )
        let game = extras.games?.first
        #expect(game?.homeScore == 21)
        #expect(game?.awayScore == 14)
        #expect(game?.userPick == "OSU")
        #expect(game?.statusText == "Q3 4:12")
        #expect(game?.isFinal == false)
        let summary = WidgetPickProgress.summarize(extras.games ?? [], now: now)
        #expect(summary?.correct == 1)
        #expect(summary?.lost == 0)
        #expect(summary?.pending == 0)
        #expect(summary?.line == "1 correct")
    }

    @Test func previousRankRemembersTheLastMove() {
        var previous = StandingsSnapshot(
            groupId: "league",
            groupName: "Saturday Crew",
            weekNumber: 6,
            seasonYear: 2026,
            userId: "u",
            userDisplayName: "You",
            weeklyWins: 4,
            weeklyLosses: 2,
            seasonWins: 10,
            seasonLosses: 4,
            rank: 5,
            totalPlayers: 12,
            topEntries: [],
            updatedAt: now
        )
        #expect(WidgetSnapshotBuilder.previousRank(currentRank: 3, previous: previous, groupId: "league", weekNumber: 6) == 5)
        previous.rank = 3
        previous.previousRank = 5
        #expect(WidgetSnapshotBuilder.previousRank(currentRank: 3, previous: previous, groupId: "league", weekNumber: 6) == 5)
        #expect(WidgetSnapshotBuilder.previousRank(currentRank: 3, previous: previous, groupId: "other", weekNumber: 6) == nil)
        #expect(WidgetSnapshotBuilder.previousRank(currentRank: 0, previous: previous, groupId: "league", weekNumber: 6) == nil)
    }

    private func counts(picks: [String: String], lockedPast: Bool) -> WidgetSnapshotBuilder.Extras {
        let past = now.addingTimeInterval(-60)
        let future = now.addingTimeInterval(3_600)
        return WidgetSnapshotBuilder.extras(
            week: week(
                status: .picking,
                pickDeadline: future,
                pickLockMode: lockedPast ? .rolling : nil
            ),
            games: [
                slate(id: "1", kickoff: lockedPast ? past : future),
                slate(id: "2", kickoff: future.addingTimeInterval(60)),
                slate(id: "3", kickoff: future.addingTimeInterval(120)),
            ],
            picks: picks,
            pickMode: .straightUp,
            now: now
        )
    }

    private func week(
        status: WeekStatus,
        weekNumber: Int = 6,
        selectionDeadline: Date? = nil,
        pickDeadline: Date? = nil,
        pickLockMode: DeadlinePolicy? = nil,
        weekLockAt: Date? = nil,
        selectionMode: SelectionMode = .member,
        selectionsPerMember: Int = 1,
        slateSize: Int = 2
    ) -> WeekSummary {
        WeekSummary(
            id: "2026-W\(weekNumber)",
            seasonYear: 2026,
            weekNumber: weekNumber,
            status: status,
            slateSize: slateSize,
            selectionMode: selectionMode,
            selectionsPerMember: selectionsPerMember,
            lockedAt: nil,
            pickDeadline: pickDeadline,
            pickLockMode: pickLockMode,
            weekLockAt: weekLockAt,
            nominationCount: 0,
            selectionDeadline: selectionDeadline
        )
    }

    private func slate(
        id: String,
        kickoff: Date,
        status: SlateGame.GameStatus = .scheduled,
        homeScore: Int? = nil,
        awayScore: Int? = nil,
        homeTeamId: String = "h",
        homeAbbreviation: String = "H",
        awayTeamId: String = "a",
        awayAbbreviation: String = "A"
    ) -> SlateGame {
        SlateGame(
            id: id,
            espnEventId: id,
            homeTeamId: homeTeamId,
            homeTeamName: "Home",
            homeTeamAbbreviation: homeAbbreviation,
            homeTeamLogoURL: nil,
            awayTeamId: awayTeamId,
            awayTeamName: "Away",
            awayTeamAbbreviation: awayAbbreviation,
            awayTeamLogoURL: nil,
            spread: 3,
            spreadTeamId: "h",
            kickoff: kickoff,
            status: status,
            homeScore: homeScore,
            awayScore: awayScore,
            winnerTeamId: nil
        )
    }

    private func nomination(eventId: String, submittedBy: String) -> Nomination {
        Nomination(
            id: eventId,
            submittedBy: submittedBy,
            submitterName: submittedBy,
            espnEventId: eventId,
            spread: 3,
            spreadTeamId: "h",
            homeTeamId: "h",
            homeTeamName: "Home",
            homeTeamAbbreviation: "H",
            homeTeamLogoURL: nil,
            awayTeamId: "a",
            awayTeamName: "Away",
            awayTeamAbbreviation: "A",
            awayTeamLogoURL: nil,
            kickoff: now,
            createdAt: now
        )
    }
}

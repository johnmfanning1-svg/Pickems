import Foundation
import Testing
@testable import Pickems

@MainActor
struct LeagueMemberProfilePolicyTests {
    @Test func scoredSheetBuildsTheWeekRecord() {
        let week = input(
            id: "2026-7",
            year: 2026,
            number: 7,
            status: .scored,
            locked: true,
            picks: ["win": "home", "loss": "home", "push": "home"],
            games: [winGame(id: "win"), lossGame(id: "loss"), pushGame(id: "push")]
        )
        let finished = LeagueMemberProfilePolicy.finishedWeeks(from: [week])
        #expect(finished.count == 1)
        #expect(finished[0].wins == 1)
        #expect(finished[0].losses == 1)
        #expect(finished[0].pushes == 1)
        #expect(finished[0].recordLabel == "1–1–1")
        #expect(finished[0].label == "2026 · Week 7")
    }

    @Test func confidencePickWeighsTheWeekTwice() {
        var week = input(
            id: "2026-8",
            year: 2026,
            number: 8,
            status: .scored,
            locked: true,
            picks: ["win": "home"],
            games: [winGame(id: "win")]
        )
        week.pick?.confidenceGameId = "win"
        let finished = LeagueMemberProfilePolicy.finishedWeeks(from: [week])
        #expect(finished.first?.wins == 2)
        #expect(finished.first?.losses == 0)
        #expect(finished.first?.recordLabel == "2–0")
    }

    @Test func openWeekStaysOffTheProfile() {
        let secret = input(
            id: "open",
            year: 2026,
            number: 4,
            status: .picking,
            locked: true,
            picks: ["win": "home", "also": "home", "third": "home"],
            games: [winGame(id: "win"), winGame(id: "also"), winGame(id: "third")]
        )
        let real = input(
            id: "scored",
            year: 2026,
            number: 3,
            status: .scored,
            locked: true,
            picks: ["loss": "home"],
            games: [lossGame(id: "loss")]
        )
        let snapshot = LeagueMemberProfilePolicy.makeSnapshot(memberWeeks: [secret, real], viewerWeeks: [])
        #expect(snapshot.bestWeeks.map(\.weekId) == ["scored"])
        #expect(snapshot.mostPicked?.teamId == "home")
        #expect(snapshot.mostPicked?.count == 1)
        #expect(LeagueMemberProfilePolicy.canSummarize(status: .picking, pick: secret.pick) == false)
        #expect(LeagueMemberProfilePolicy.canSummarize(status: .selection, pick: secret.pick) == false)
    }

    @Test func unlockedSheetOnALockedWeekStaysOffTheProfile() {
        let unlocked = input(
            id: "locked-week",
            year: 2026,
            number: 5,
            status: .locked,
            locked: false,
            picks: ["win": "home", "also": "home"],
            games: [winGame(id: "win"), winGame(id: "also")]
        )
        let snapshot = LeagueMemberProfilePolicy.makeSnapshot(memberWeeks: [unlocked], viewerWeeks: [])
        #expect(snapshot.bestWeeks.isEmpty)
        #expect(snapshot.mostPicked == nil)
        #expect(snapshot.streak == 0)
        #expect(LeagueMemberProfilePolicy.canSummarize(status: .locked, pick: unlocked.pick) == false)
    }

    @Test func scoredSheetCountsWhenItWasNeverLocked() {
        let final = input(
            id: "final",
            year: 2026,
            number: 6,
            status: .scored,
            locked: false,
            picks: ["win": "home"],
            games: [winGame(id: "win")]
        )
        let snapshot = LeagueMemberProfilePolicy.makeSnapshot(memberWeeks: [final], viewerWeeks: [])
        #expect(snapshot.bestWeeks.map(\.recordLabel) == ["1–0"])
        #expect(snapshot.mostPicked?.count == 1)
        #expect(snapshot.winningWeeks == 1)
    }

    @Test func bestWeeksRankWinsThenFewerLosses() {
        let weeks = [
            finished("a", year: 2025, number: 2, wins: 8, losses: 3),
            finished("b", year: 2026, number: 1, wins: 9, losses: 2),
            finished("c", year: 2026, number: 4, wins: 8, losses: 1),
            finished("d", year: 2026, number: 9, wins: 7, losses: 0),
        ]
        let best = LeagueMemberProfilePolicy.bestWeeks(weeks)
        #expect(best.map(\.weekId) == ["b", "c", "a"])
        #expect(LeagueMemberProfilePolicy.bestWeeks([], limit: 3).isEmpty)
    }

    @Test func mostPickedUsesLockedSheetsAndSkipsUnknownTeams() {
        let hidden = input(
            id: "open",
            year: 2026,
            number: 1,
            status: .picking,
            locked: true,
            picks: ["s1": "secret", "s2": "secret", "s3": "secret"],
            games: [
                matchup(id: "s1", home: "secret", homeAbbr: "SEC"),
                matchup(id: "s2", home: "secret", homeAbbr: "SEC"),
                matchup(id: "s3", home: "secret", homeAbbr: "SEC"),
            ]
        )
        let counted = input(
            id: "locked",
            year: 2026,
            number: 2,
            status: .locked,
            locked: true,
            picks: ["g1": "ala", "g2": "ghost"],
            games: [
                matchup(id: "g1", home: "ala", homeName: "Alabama", homeAbbr: "ALA", away: "uga", awayName: "Georgia", awayAbbr: "UGA"),
                matchup(id: "g2", home: "home", homeAbbr: "HOM", away: "away", awayAbbr: "AWY"),
            ]
        )
        let tally = LeagueMemberProfilePolicy.mostPickedTeam(from: [hidden, counted])
        #expect(tally?.teamId == "ala")
        #expect(tally?.name == "Alabama")
        #expect(tally?.abbreviation == "ALA")
        #expect(tally?.count == 1)
    }

    @Test func mostPickedTieBreaksByAbbreviation() {
        let week = input(
            id: "tie",
            year: 2026,
            number: 2,
            status: .locked,
            locked: true,
            picks: ["g1": "miz", "g2": "ala"],
            games: [
                matchup(id: "g1", home: "miz", homeName: "Missouri", homeAbbr: "MIZ"),
                matchup(id: "g2", home: "ala", homeName: "Alabama", homeAbbr: "ALA"),
            ]
        )
        let tally = LeagueMemberProfilePolicy.mostPickedTeam(from: [week])
        #expect(tally?.abbreviation == "ALA")
        #expect(tally?.count == 1)
    }

    @Test func streakFollowsSeasonThenWeek() {
        let broken = LeagueMemberProfilePolicy.streak(from: [
            finished("later", year: 2026, number: 1, wins: 0, losses: 4),
            finished("early", year: 2025, number: 1, wins: 4, losses: 1),
            finished("mid", year: 2025, number: 2, wins: 3, losses: 1),
        ])
        #expect(broken == 0)

        let heater = LeagueMemberProfilePolicy.streak(from: [
            finished("w3", year: 2026, number: 3, wins: 4, losses: 1),
            finished("w1", year: 2026, number: 1, wins: 1, losses: 4),
            finished("w2", year: 2026, number: 2, wins: 3, losses: 2),
        ])
        #expect(heater == 2)
    }

    @Test func headToHeadSkipsWeeksOnlyOneSideFinished() {
        let member = [
            finished("shared-a", year: 2026, number: 1, wins: 5, losses: 1),
            finished("shared-b", year: 2026, number: 2, wins: 1, losses: 5),
            finished("member-only", year: 2026, number: 3, wins: 6, losses: 0),
        ]
        let viewer = [
            finished("shared-a", year: 2026, number: 1, wins: 2, losses: 4),
            finished("shared-b", year: 2026, number: 2, wins: 1, losses: 5),
            finished("viewer-only", year: 2026, number: 4, wins: 4, losses: 0),
        ]
        let head = LeagueMemberProfilePolicy.headToHead(memberWeeks: member, viewerWeeks: viewer)
        #expect(head?.viewerWeekWins == 0)
        #expect(head?.memberWeekWins == 1)
        #expect(head?.ties == 1)
        #expect(head?.weeksCompared == 2)
        #expect(LeagueMemberProfilePolicy.headToHead(memberWeeks: member, viewerWeeks: []) == nil)
    }

    @Test func careerTotalsAddThisSeasonForAMember() {
        let totals = LeagueMemberProfilePolicy.careerTotals(
            closed: career(wins: 20, losses: 10, seasons: 2, titles: 1, best: 1),
            currentWins: 8,
            currentLosses: 4,
            isCurrentMember: true
        )
        #expect(totals.wins == 28)
        #expect(totals.losses == 14)
        #expect(totals.seasons == 3)
        #expect(totals.titles == 1)
        #expect(totals.bestFinish == 1)
        #expect(totals.hasClosedHistory)
        #expect(totals.recordLabel == "28–14")
    }

    @Test func careerTotalsStayClosedAfterLeaving() {
        let totals = LeagueMemberProfilePolicy.careerTotals(
            closed: career(wins: 20, losses: 10, seasons: 2, titles: 1, best: 2),
            currentWins: 8,
            currentLosses: 4,
            isCurrentMember: false
        )
        #expect(totals.wins == 20)
        #expect(totals.losses == 10)
        #expect(totals.seasons == 2)
        #expect(totals.recordLabel == "20–10")

        let brandNew = LeagueMemberProfilePolicy.careerTotals(
            closed: nil,
            currentWins: 0,
            currentLosses: 0,
            isCurrentMember: true
        )
        #expect(brandNew.hasClosedHistory == false)
        #expect(brandNew.seasons == 1)
        #expect(brandNew.recordLabel == "0–0")
    }

    @Test func outsiderIsNotALeagueSubject() {
        #expect(LeagueMemberProfilePolicy.isLeagueSubject(userId: "c", memberIds: ["a"], careerIds: ["b"]) == false)
        #expect(LeagueMemberProfilePolicy.isLeagueSubject(userId: "a", memberIds: ["a"], careerIds: []) == true)
        #expect(LeagueMemberProfilePolicy.isLeagueSubject(userId: "b", memberIds: [], careerIds: ["b"]) == true)
        #expect(LeagueMemberProfilePolicy.isLeagueSubject(userId: "", memberIds: [String](), careerIds: [String]()) == false)
    }

    @Test func winningWeeksCountOnlyWeeksAhead() {
        let weeks = [
            finished("ahead", year: 2026, number: 1, wins: 3, losses: 1),
            finished("tied", year: 2026, number: 2, wins: 2, losses: 2),
            finished("behind", year: 2026, number: 3, wins: 1, losses: 4),
            finished("pushy", year: 2026, number: 4, wins: 1, losses: 0, pushes: 3),
        ]
        #expect(LeagueMemberProfilePolicy.winningWeekCount(weeks) == 2)
    }

    private func input(
        id: String,
        year: Int,
        number: Int,
        status: WeekStatus,
        locked: Bool,
        picks: [String: String],
        games: [SlateGame]
    ) -> LeagueMemberProfilePolicy.WeekInput {
        LeagueMemberProfilePolicy.WeekInput(
            weekId: id,
            seasonYear: year,
            weekNumber: number,
            status: status,
            pickMode: .ats,
            pick: LeagueMemberProfilePolicy.PickSheet(
                isLocked: locked,
                picks: picks,
                confidenceGameId: nil
            ),
            games: games
        )
    }

    private func finished(
        _ id: String,
        year: Int,
        number: Int,
        wins: Int,
        losses: Int,
        pushes: Int = 0
    ) -> LeagueMemberProfilePolicy.FinishedWeek {
        LeagueMemberProfilePolicy.FinishedWeek(
            weekId: id,
            seasonYear: year,
            weekNumber: number,
            wins: wins,
            losses: losses,
            pushes: pushes
        )
    }

    private func career(
        wins: Int,
        losses: Int,
        seasons: Int,
        titles: Int,
        best: Int?
    ) -> CareerRecord {
        CareerRecord(
            id: "member",
            displayName: "Alex",
            avatarColorHex: "#DC2626",
            titles: titles,
            seasonWins: wins,
            seasonLosses: losses,
            seasonsPlayed: seasons,
            bestFinish: best,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func winGame(id: String) -> SlateGame {
        matchup(id: id, homeScore: 28, awayScore: 7, spread: 3, status: .final)
    }

    private func lossGame(id: String) -> SlateGame {
        matchup(id: id, homeScore: 10, awayScore: 24, spread: 3, status: .final)
    }

    private func pushGame(id: String) -> SlateGame {
        matchup(id: id, homeScore: 14, awayScore: 7, spread: 7, status: .final)
    }

    private func matchup(
        id: String,
        home: String = "home",
        homeName: String = "Home",
        homeAbbr: String = "HOM",
        away: String = "away",
        awayName: String = "Away",
        awayAbbr: String = "AWY",
        homeScore: Int? = nil,
        awayScore: Int? = nil,
        spread: Double = 3,
        status: SlateGame.GameStatus = .scheduled
    ) -> SlateGame {
        SlateGame(
            id: id,
            espnEventId: id,
            homeTeamId: home,
            homeTeamName: homeName,
            homeTeamAbbreviation: homeAbbr,
            homeTeamLogoURL: nil,
            awayTeamId: away,
            awayTeamName: awayName,
            awayTeamAbbreviation: awayAbbr,
            awayTeamLogoURL: nil,
            spread: spread,
            spreadTeamId: home,
            kickoff: Date(timeIntervalSince1970: 0),
            status: status,
            homeScore: homeScore,
            awayScore: awayScore,
            winnerTeamId: nil
        )
    }
}

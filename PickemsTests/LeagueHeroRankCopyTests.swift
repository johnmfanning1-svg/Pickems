import Foundation
import Testing
@testable import Pickems

struct LeagueHeroRankCopyTests {
    @Test func scorelessRecordUsesADashInsteadOfJoinOrderRank() {
        let weekly = LeagueHeroRankCopy.Member(id: "me", wins: 0, losses: 0, rank: 1, isTied: false)
        let earlierJoin = LeagueHeroRankCopy.Member(id: "early", wins: 0, losses: 0, rank: 2, isTied: false)
        let season = LeagueHeroRankCopy.Member(id: "me", wins: 59, losses: 66, rank: 3, isTied: false)
        let copy = LeagueHeroRankCopy.display(
            weekly: weekly,
            weeklyBoard: [weekly, earlierJoin],
            season: season,
            seasonBoard: [season]
        )

        #expect(copy.weeklyRecord.value == "0\u{2013}0")
        #expect(copy.weeklyRecord.label == "This Week")
        #expect(copy.weeklyRank.value == "\u{2014}")
        #expect(copy.weeklyRank.label == "This Week Rank")
        #expect(copy.seasonRecord.value == "59\u{2013}66")
        #expect(copy.seasonRecord.label == "Season")
        #expect(copy.seasonRank.value == "#3")
        #expect(copy.seasonRank.label == "Season Rank")
        #expect(copy.accessibilityLabel == "Week 0 to 0, season 59 to 66, No this week rank yet, Season rank 3")
        #expect(!copy.accessibilityLabel.contains("rank 1"))

        let decidedLoss = LeagueHeroRankCopy.Member(id: "me", wins: 0, losses: 2, rank: 4, isTied: false)
        let emptySeason = LeagueHeroRankCopy.Member(id: "me", wins: 0, losses: 0, rank: 1, isTied: false)
        let lossWeek = LeagueHeroRankCopy.display(
            weekly: decidedLoss,
            weeklyBoard: [decidedLoss],
            season: emptySeason,
            seasonBoard: [emptySeason]
        )
        #expect(lossWeek.weeklyRank.value == "#4")
        #expect(lossWeek.weeklyRank.label == "This Week Rank")
        #expect(lossWeek.seasonRank.value == "\u{2014}")
        #expect(lossWeek.seasonRank.label == "Season Rank")
        #expect(lossWeek.accessibilityLabel == "Week 0 to 2, season 0 to 0, This week rank 4, No season rank yet")
    }

    @Test func labelsSeparateThisWeekRankFromSeasonRank() {
        let weekly = LeagueHeroRankCopy.member(
            id: "me",
            weeklyWins: 0,
            weeklyLosses: 0,
            seasonWins: 59,
            seasonLosses: 66,
            rank: 1,
            isTied: false,
            weeklyScope: true
        )
        let season = LeagueHeroRankCopy.member(
            id: "me",
            weeklyWins: 0,
            weeklyLosses: 0,
            seasonWins: 59,
            seasonLosses: 66,
            rank: 3,
            isTied: false,
            weeklyScope: false
        )
        #expect(weekly.wins == 0)
        #expect(weekly.losses == 0)
        #expect(season.wins == 59)
        #expect(season.losses == 66)

        let swapped = LeagueHeroRankCopy.member(
            id: "me",
            weeklyWins: 8,
            weeklyLosses: 1,
            seasonWins: 2,
            seasonLosses: 9,
            rank: 2,
            isTied: false,
            weeklyScope: false
        )
        #expect(swapped.wins == 2)
        #expect(swapped.losses == 9)

        let copy = LeagueHeroRankCopy.display(
            weekly: weekly,
            weeklyBoard: [weekly],
            season: season,
            seasonBoard: [season]
        )
        #expect(copy.weeklyRecord.label == "This Week")
        #expect(copy.seasonRecord.label == "Season")
        #expect(copy.weeklyRank.label == "This Week Rank")
        #expect(copy.seasonRank.label == "Season Rank")
        #expect(copy.weeklyRecord.value == "0\u{2013}0")
        #expect(copy.seasonRecord.value == "59\u{2013}66")
        #expect(copy.accessibilityLabel.contains("No this week rank yet"))
        #expect(copy.accessibilityLabel.contains("Season rank 3"))
    }

    @Test func tiedRanksUseTheTPrefix() {
        // Scoring leaves isTied false on the first member of a shared rank.
        let weeklyLeader = LeagueHeroRankCopy.Member(id: "me", wins: 4, losses: 1, rank: 1, isTied: false)
        let weeklyPeer = LeagueHeroRankCopy.Member(id: "them", wins: 4, losses: 1, rank: 1, isTied: true)
        let season = LeagueHeroRankCopy.Member(id: "me", wins: 59, losses: 66, rank: 3, isTied: false)
        let weeklyTie = LeagueHeroRankCopy.display(
            weekly: weeklyLeader,
            weeklyBoard: [weeklyLeader, weeklyPeer],
            season: season,
            seasonBoard: [season]
        )
        #expect(weeklyTie.weeklyRank.value == "T-#1")
        #expect(weeklyTie.weeklyRank.label == "This Week Rank")
        #expect(weeklyTie.seasonRank.value == "#3")
        #expect(weeklyTie.seasonRank.label == "Season Rank")
        #expect(weeklyTie.accessibilityLabel == "Week 4 to 1, season 59 to 66, Tied for this week rank 1, Season rank 3")

        let weekSolo = LeagueHeroRankCopy.Member(id: "me", wins: 5, losses: 2, rank: 4, isTied: false)
        let seasonLeader = LeagueHeroRankCopy.Member(id: "me", wins: 60, losses: 65, rank: 2, isTied: false)
        let seasonPeer = LeagueHeroRankCopy.Member(id: "them", wins: 60, losses: 65, rank: 2, isTied: true)
        let seasonTie = LeagueHeroRankCopy.display(
            weekly: weekSolo,
            weeklyBoard: [weekSolo],
            season: seasonLeader,
            seasonBoard: [seasonLeader, seasonPeer]
        )
        #expect(seasonTie.weeklyRank.value == "#4")
        #expect(seasonTie.seasonRank.value == "T-#2")
        #expect(seasonTie.accessibilityLabel.contains("This week rank 4"))
        #expect(seasonTie.accessibilityLabel.contains("Tied for season rank 2"))

        let flagged = LeagueHeroRankCopy.Member(id: "me", wins: 3, losses: 3, rank: 2, isTied: true)
        let flaggedCopy = LeagueHeroRankCopy.display(
            weekly: flagged,
            weeklyBoard: [flagged],
            season: season,
            seasonBoard: [season]
        )
        #expect(flaggedCopy.weeklyRank.value == "T-#2")
        #expect(flaggedCopy.seasonRank.value == "#3")
    }
}

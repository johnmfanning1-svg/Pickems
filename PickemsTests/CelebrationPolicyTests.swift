import Foundation
import Testing
@testable import Pickems

struct CelebrationPolicyTests {
    @Test func firstObservationSeedsFinalsAndPresentsNothing() {
        let games = [
            CelebrationPolicy.ObservedGame(id: "final-win", isFinal: true, isCorrect: true, isPush: false),
            CelebrationPolicy.ObservedGame(id: "final-miss", isFinal: true, isCorrect: false, isPush: false),
            CelebrationPolicy.ObservedGame(id: "live", isFinal: false, isCorrect: nil, isPush: false)
        ]
        let first = CelebrationPolicy.observe(
            games: games,
            previouslySeen: [],
            isFirstObservation: true,
            isForeground: true,
            absorbCurrentlyFinal: false,
            winTitle: "Covered"
        )
        #expect(first.sheetGameId == nil)
        #expect(first.inline.isEmpty)
        #expect(first.seen == ["final-win", "final-miss"])

        let again = CelebrationPolicy.observe(
            games: games,
            previouslySeen: first.seen,
            isFirstObservation: false,
            isForeground: true,
            absorbCurrentlyFinal: false,
            winTitle: "Covered"
        )
        #expect(again.sheetGameId == nil)
        #expect(again.inline.isEmpty)
    }

    @Test func foregroundCorrectFinalPresentsASheetAndAMissOrPushStaysInline() {
        let seen: Set<String> = ["already"]
        let win = CelebrationPolicy.observe(
            games: [CelebrationPolicy.ObservedGame(id: "new", isFinal: true, isCorrect: true, isPush: false)],
            previouslySeen: seen,
            isFirstObservation: false,
            isForeground: true,
            absorbCurrentlyFinal: false,
            winTitle: "Covered"
        )
        #expect(win.sheetGameId == "new")
        #expect(win.inline["new"] == .win(title: "Covered"))
        #expect(win.seen.contains("new"))

        let miss = CelebrationPolicy.observe(
            games: [CelebrationPolicy.ObservedGame(id: "miss", isFinal: true, isCorrect: false, isPush: false)],
            previouslySeen: seen,
            isFirstObservation: false,
            isForeground: true,
            absorbCurrentlyFinal: false,
            winTitle: "Won"
        )
        #expect(miss.sheetGameId == nil)
        #expect(miss.inline["miss"] == .miss)

        let push = CelebrationPolicy.observe(
            games: [CelebrationPolicy.ObservedGame(id: "push", isFinal: true, isCorrect: nil, isPush: true)],
            previouslySeen: seen,
            isFirstObservation: false,
            isForeground: true,
            absorbCurrentlyFinal: false,
            winTitle: "Covered"
        )
        #expect(push.sheetGameId == nil)
        #expect(push.inline["push"] == .push)
    }

    @Test func backgroundAndFreshForegroundAbsorbDoNotPresent() {
        let game = CelebrationPolicy.ObservedGame(id: "late", isFinal: true, isCorrect: true, isPush: false)
        let background = CelebrationPolicy.observe(
            games: [game],
            previouslySeen: [],
            isFirstObservation: false,
            isForeground: false,
            absorbCurrentlyFinal: false,
            winTitle: "Covered"
        )
        #expect(background.sheetGameId == nil)
        #expect(background.inline.isEmpty)
        #expect(background.seen == ["late"])

        let absorb = CelebrationPolicy.observe(
            games: [game],
            previouslySeen: [],
            isFirstObservation: false,
            isForeground: true,
            absorbCurrentlyFinal: true,
            winTitle: "Covered"
        )
        #expect(absorb.sheetGameId == nil)
        #expect(absorb.seen == ["late"])
    }

    @Test func hapticIsSuccessOnlyOnAWin() {
        #expect(CelebrationPolicy.haptic(for: .win(title: "Covered")) == .success)
        #expect(CelebrationPolicy.haptic(for: .win(title: "Won")) == .success)
        #expect(CelebrationPolicy.haptic(for: .miss) == .none)
        #expect(CelebrationPolicy.haptic(for: .push) == .none)

        let watching = CelebrationPolicy.watchingEffect(
            wasWatching: true,
            becameFinal: true,
            result: .win,
            winTitle: "Covered",
            awayName: "Georgia",
            homeName: "Alabama",
            isNeutral: false
        )
        #expect(watching?.feedback == .success)
        #expect(watching?.announcement == "Covered, Georgia at Alabama")

        let miss = CelebrationPolicy.watchingEffect(
            wasWatching: true,
            becameFinal: true,
            result: .loss,
            winTitle: "Covered",
            awayName: "Georgia",
            homeName: "Alabama",
            isNeutral: false
        )
        #expect(miss?.feedback == CelebrationPolicy.Feedback.none)
        #expect(miss?.announcement == "Missed, Georgia at Alabama")

        let alreadyFinal = CelebrationPolicy.watchingEffect(
            wasWatching: false,
            becameFinal: true,
            result: .win,
            winTitle: "Covered",
            awayName: "Georgia",
            homeName: "Alabama",
            isNeutral: false
        )
        #expect(alreadyFinal == nil)

        let neutral = CelebrationPolicy.announcement(
            inline: .push,
            awayName: "Army",
            homeName: "Navy",
            isNeutral: true
        )
        #expect(neutral == "Push, Army vs Navy")
    }

    @Test func weekWinRequiresAScoredSoleOrTiedLeader() {
        let champ = CelebrationPolicy.WeekBoardEntry(
            id: "me", rank: 1, isTied: false, weeklyWins: 8, weeklyLosses: 2
        )
        let rival = CelebrationPolicy.WeekBoardEntry(
            id: "them", rank: 2, isTied: false, weeklyWins: 7, weeklyLosses: 3
        )
        #expect(
            CelebrationPolicy.weekWinKind(entries: [champ, rival], userId: "me", weekStatus: .scored) == .champ
        )
        #expect(CelebrationPolicy.WeekWinKind.champ.title(weekNumber: 8) == "Week 8 Champ")

        let tiedLeader = CelebrationPolicy.WeekBoardEntry(
            id: "me", rank: 1, isTied: false, weeklyWins: 8, weeklyLosses: 2
        )
        let tiedPeer = CelebrationPolicy.WeekBoardEntry(
            id: "them", rank: 1, isTied: true, weeklyWins: 8, weeklyLosses: 2
        )
        #expect(
            CelebrationPolicy.weekWinKind(entries: [tiedLeader, tiedPeer], userId: "me", weekStatus: .scored) == .coChamp
        )
        #expect(
            CelebrationPolicy.weekWinKind(entries: [tiedLeader, tiedPeer], userId: "them", weekStatus: .scored) == .coChamp
        )
        #expect(CelebrationPolicy.WeekWinKind.coChamp.title(weekNumber: 8) == "Week 8 Co-Champ")

        let flagged = CelebrationPolicy.WeekBoardEntry(
            id: "me", rank: 1, isTied: true, weeklyWins: 5, weeklyLosses: 1
        )
        #expect(CelebrationPolicy.weekWinKind(entries: [flagged], userId: "me", weekStatus: .scored) == .coChamp)

        let empty = CelebrationPolicy.WeekBoardEntry(
            id: "me", rank: 1, isTied: false, weeklyWins: 0, weeklyLosses: 0
        )
        #expect(CelebrationPolicy.weekWinKind(entries: [empty], userId: "me", weekStatus: .scored) == nil)
        #expect(CelebrationPolicy.weekWinKind(entries: [champ], userId: "me", weekStatus: .locked) == nil)
        #expect(CelebrationPolicy.weekWinKind(entries: [champ], userId: "me", weekStatus: .picking) == nil)
        #expect(CelebrationPolicy.weekWinKind(entries: [rival], userId: "them", weekStatus: .scored) == nil)
    }

    @Test func weekWinKeyIsNotShownTwiceAndSeenFinalsRoundTrip() {
        let defaults = UserDefaults(suiteName: "CelebrationPolicyTests.week")!
        defaults.removePersistentDomain(forName: "CelebrationPolicyTests.week")
        let groupId = "league"
        let weekId = "2026-W8"

        #expect(CelebrationStore.weekWinKey(groupId: groupId, weekId: weekId) == "celebrated.weekWin.league.2026-W8")
        #expect(!CelebrationStore.hasCelebratedWeekWin(groupId: groupId, weekId: weekId, defaults: defaults))
        #expect(CelebrationPolicy.shouldShowWeekWin(kind: .champ, alreadyCelebrated: false))

        CelebrationStore.markWeekWinCelebrated(groupId: groupId, weekId: weekId, defaults: defaults)
        let again = CelebrationStore.hasCelebratedWeekWin(groupId: groupId, weekId: weekId, defaults: defaults)
        #expect(again)
        #expect(!CelebrationPolicy.shouldShowWeekWin(kind: .champ, alreadyCelebrated: again))
        #expect(!CelebrationPolicy.shouldShowWeekWin(kind: nil, alreadyCelebrated: false))

        CelebrationStore.saveSeenFinals(["b", "a"], groupId: groupId, weekId: weekId, defaults: defaults)
        #expect(
            CelebrationStore.loadSeenFinals(groupId: groupId, weekId: weekId, defaults: defaults) == ["a", "b"]
        )
    }

    @Test func pulseRankHidesAScorelessWeekAndPrefixesATie() {
        let empty = standing(id: "me", rank: 1, tied: false, wins: 0, losses: 0)
        let hidden = PulseRankCopy.display(entry: empty, board: [empty])
        #expect(hidden.rankText == "—")
        #expect(hidden.detailText == "No games final yet")
        #expect(hidden.animatableRank == nil)

        let leader = standing(id: "me", rank: 1, tied: false, wins: 4, losses: 1)
        let peer = standing(id: "them", rank: 1, tied: true, wins: 4, losses: 1)
        let tied = PulseRankCopy.display(entry: leader, board: [leader, peer])
        #expect(tied.rankText == "T-#1")
        #expect(tied.accessibilityRank == "Tied for rank 1")

        let second = standing(id: "me", rank: 2, tied: true, wins: 3, losses: 2)
        let prefixed = PulseRankCopy.display(entry: second, board: [second])
        #expect(prefixed.rankText == "T-#2")
        #expect(prefixed.detailText == "3–2 this week")

        let solo = PulseRankCopy.display(entry: leader, board: [leader])
        #expect(solo.rankText == "#1")
        #expect(solo.animatableRank == 1)
    }

    private func standing(
        id: String,
        rank: Int,
        tied: Bool,
        wins: Int,
        losses: Int
    ) -> StandingEntry {
        StandingEntry(
            id: id,
            displayName: id,
            avatarColorHex: "#DC2626",
            weeklyWins: wins,
            weeklyLosses: losses,
            seasonWins: wins,
            seasonLosses: losses,
            rank: rank,
            isTied: tied
        )
    }
}

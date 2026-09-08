import Foundation
import Testing
@testable import Pickems

struct LeagueWeekRecapGeneratorTests {
    @Test func joinNamesFormatsOneTwoAndMany() {
        #expect(LeagueWeekRecapGenerator.joinNames(["Ace"]) == "Ace")
        #expect(LeagueWeekRecapGenerator.joinNames(["Ace", "Bo"]) == "Ace and Bo")
        #expect(LeagueWeekRecapGenerator.joinNames(["Ace", "Bo", "Cam"]) == "Ace, Bo, and Cam")
    }

    @Test func scoredRecapNamesWinnerAndLastPlace() {
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 8, losses: 3, rank: 1),
                entry(id: "b", name: "Bo", wins: 6, losses: 5, rank: 2),
                entry(id: "c", name: "Cam", wins: 3, losses: 8, rank: 3)
            ]
        )
        #expect(recap.headline == "Core 4 OG — Week 1")
        #expect(recap.winnerLine == "Winner: Ace 8–3")
        #expect(recap.lastPlaceLine == "Last place: Cam 3–8")
        #expect(recap.shareText.contains("Your week") == false)
        #expect(recap.highlightLine == "2 of 3 posted a winning record.")
    }

    @Test func tiedWinnerAndTiedLastPlace() {
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 7, losses: 4, rank: 1, tied: true),
                entry(id: "b", name: "Bo", wins: 7, losses: 4, rank: 1, tied: true),
                entry(id: "c", name: "Cam", wins: 4, losses: 7, rank: 3, tied: true),
                entry(id: "d", name: "Dee", wins: 4, losses: 7, rank: 3, tied: true)
            ]
        )
        #expect(recap.winnerLine == "Winner (tie): Ace and Bo at 7–4")
        #expect(recap.lastPlaceLine == "Last place (tie): Cam and Dee at 4–7")
    }

    @Test func skipsLastPlaceWhenEveryoneTied() {
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 5, losses: 5, rank: 1, tied: true),
                entry(id: "b", name: "Bo", wins: 5, losses: 5, rank: 1, tied: true)
            ]
        )
        #expect(recap.winnerLine == "Winner (tie): Ace and Bo at 5–5")
        #expect(recap.lastPlaceLine == nil)
    }

    @Test func inProgressUsesLeaderLanguage() {
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .locked),
            entries: [
                entry(id: "a", name: "Ace", wins: 5, losses: 2, rank: 1),
                entry(id: "c", name: "Cam", wins: 1, losses: 6, rank: 2)
            ]
        )
        #expect(recap.headline.contains("in progress"))
        #expect(recap.winnerLine == "Leader so far: Ace 5–2")
        #expect(recap.lastPlaceLine == "Last for now: Cam 1–6")
        #expect(recap.isFinal == false)
    }

    @Test func perfectSaturdayBeatsOtherHighlights() {
        let games = [finalGame("1", homeCovers: true), finalGame("2", homeCovers: true)]
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 2, losses: 0, rank: 1),
                entry(id: "c", name: "Cam", wins: 0, losses: 2, rank: 2)
            ],
            games: games
        )
        #expect(recap.highlightLine == "Ace ran the table at 2–0.")
    }

    @Test func chalkBustWhenMajorityMisses() {
        let games = [
            finalGame("g1", homeCovers: false),
            finalGame("g2", homeCovers: true),
            finalGame("g3", homeCovers: true)
        ]
        let picks = [
            pick("a", "Ace", ["g1": "home", "g2": "home", "g3": "home"]),
            pick("b", "Bo", ["g1": "home", "g2": "home", "g3": "away"]),
            pick("c", "Cam", ["g1": "home", "g2": "away", "g3": "home"]),
            pick("d", "Dee", ["g1": "away", "g2": "home", "g3": "home"])
        ]
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 2, losses: 1, rank: 1),
                entry(id: "b", name: "Bo", wins: 1, losses: 2, rank: 2),
                entry(id: "c", name: "Cam", wins: 1, losses: 2, rank: 2),
                entry(id: "d", name: "Dee", wins: 1, losses: 2, rank: 2)
            ],
            picks: picks,
            games: games
        )
        #expect(recap.highlightLine == "The league faded AWY. Only 1 of 4 had them.")
        #expect(recap.winnerLine == "Winner: Ace 2–1")
        #expect(recap.lastPlaceLine == "Last place (tie): Bo, Cam, and Dee at 1–2")
    }

    @Test func photoFinishWhenSeparatedByOneWin() {
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 8, losses: 3, rank: 1),
                entry(id: "b", name: "Bo", wins: 7, losses: 4, rank: 2)
            ]
        )
        #expect(recap.highlightLine == "Ace nipped Bo by a game (8–3 vs 7–4).")
    }

    @Test func contrarianHighlightSkipsTheWinner() {
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 9, losses: 2, rank: 1),
                entry(id: "b", name: "Bo", wins: 5, losses: 6, rank: 2)
            ],
            awards: WeekAwards(sharpshooterUserId: nil, heartbreakerUserId: nil, contrarianUserId: "b")
        )
        #expect(recap.highlightLine == "Bo was the Contrarian — unique covers nobody else had.")
    }

    @Test func edgyToneRoastsWinnerAndLastPlace() {
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 8, losses: 3, rank: 1),
                entry(id: "b", name: "Bo", wins: 6, losses: 5, rank: 2),
                entry(id: "c", name: "Cam", wins: 3, losses: 8, rank: 3)
            ],
            tone: .edgy
        )
        #expect(recap.winnerLine == "Winner: Ace 8–3. Everyone else played for second.")
        #expect(recap.lastPlaceLine == "Last place: Cam 3–8. That's a week you bury.")
        #expect(recap.highlightLine == "2 of 3 posted a winning record. The rest know who they are.")
    }

    @Test func edgyTiedWinnerAndLastPlace() {
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 7, losses: 4, rank: 1, tied: true),
                entry(id: "b", name: "Bo", wins: 7, losses: 4, rank: 1, tied: true),
                entry(id: "c", name: "Cam", wins: 4, losses: 7, rank: 3, tied: true),
                entry(id: "d", name: "Dee", wins: 4, losses: 7, rank: 3, tied: true)
            ],
            tone: .edgy
        )
        #expect(recap.winnerLine == "Split crown: Ace and Bo at 7–4. The rest of you weren't invited.")
        #expect(recap.lastPlaceLine == "Basement (tie): Cam and Dee at 4–7. Misery loves company.")
    }

    @Test func edgyChalkBust() {
        let games = [
            finalGame("g1", homeCovers: false),
            finalGame("g2", homeCovers: true),
            finalGame("g3", homeCovers: true)
        ]
        let picks = [
            pick("a", "Ace", ["g1": "home", "g2": "home", "g3": "home"]),
            pick("b", "Bo", ["g1": "home", "g2": "home", "g3": "away"]),
            pick("c", "Cam", ["g1": "home", "g2": "away", "g3": "home"]),
            pick("d", "Dee", ["g1": "away", "g2": "home", "g3": "home"])
        ]
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 2, losses: 1, rank: 1),
                entry(id: "b", name: "Bo", wins: 1, losses: 2, rank: 2),
                entry(id: "c", name: "Cam", wins: 1, losses: 2, rank: 2),
                entry(id: "d", name: "Dee", wins: 1, losses: 2, rank: 2)
            ],
            picks: picks,
            games: games,
            tone: .edgy
        )
        #expect(recap.highlightLine == "The league faded AWY and ate it. Only 1 of 4 had them.")
    }

    @Test func edgyPhotoFinish() {
        let recap = LeagueWeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 8, losses: 3, rank: 1),
                entry(id: "b", name: "Bo", wins: 7, losses: 4, rank: 2)
            ],
            tone: .edgy
        )
        #expect(recap.highlightLine == "Ace nipped Bo by a game (8–3 vs 7–4). Sleep tight, Bo.")
    }

    private func week(status: WeekStatus) -> WeekSummary {
        WeekSummary(
            id: "2026-W1",
            seasonYear: 2026,
            weekNumber: 1,
            status: status,
            slateSize: 11,
            selectionMode: .member,
            selectionsPerMember: 1,
            nominationCount: 0
        )
    }

    private func entry(
        id: String,
        name: String,
        wins: Int,
        losses: Int,
        rank: Int,
        tied: Bool = false
    ) -> StandingEntry {
        StandingEntry(
            id: id,
            displayName: name,
            avatarColorHex: "#DC2626",
            weeklyWins: wins,
            weeklyLosses: losses,
            seasonWins: wins,
            seasonLosses: losses,
            rank: rank,
            isTied: tied
        )
    }

    private func pick(_ id: String, _ name: String, _ picks: [String: String]) -> UserPick {
        UserPick(id: id, userId: id, displayName: name, picks: picks, submittedAt: Date(), isLocked: true)
    }

    private func finalGame(_ id: String, homeCovers: Bool) -> SlateGame {
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
            kickoff: Date(),
            status: .final,
            homeScore: homeCovers ? 28 : 10,
            awayScore: homeCovers ? 17 : 24,
            winnerTeamId: homeCovers ? "home" : "away"
        )
    }
}

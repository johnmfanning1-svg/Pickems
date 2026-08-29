import Foundation
import Testing
@testable import Pickems

struct SlateGameDecodingTests {
    @Test func missingIdUsesDocumentId() {
        let game = SlateGameDecoding.make(
            documentId: "401671749",
            data: [
                "espnEventId": "401671749",
                "homeTeamName": "Alabama",
                "awayTeamName": "Georgia",
                "spread": 3.5,
                "spreadTeamId": "333",
                "homeTeamId": "333",
                "awayTeamId": "61",
            ],
            kickoff: Date(timeIntervalSince1970: 1_777_000_000)
        )
        #expect(game?.id == "401671749")
        #expect(game?.espnEventId == "401671749")
        #expect(game?.spread == 3.5)
        #expect(game?.homeTeamAbbreviation == "ALAB")
    }

    @Test func numericIdsCoerceToString() {
        let game = SlateGameDecoding.make(
            documentId: "401671749",
            data: [
                "id": 401671749,
                "espnEventId": 401671749,
                "homeTeamName": "Home",
                "awayTeamName": "Away",
                "homeTeamId": 333,
                "awayTeamId": 61,
                "spread": 7,
            ],
            kickoff: Date()
        )
        #expect(game?.id == "401671749")
        #expect(game?.espnEventId == "401671749")
        #expect(game?.homeTeamId == "333")
        #expect(game?.spread == 7)
    }

    @Test func fieldIdWinsOverDocumentId() {
        let game = SlateGameDecoding.make(
            documentId: "doc-id",
            data: [
                "id": "field-id",
                "espnEventId": "espn-id",
                "homeTeamName": "Home",
                "awayTeamName": "Away",
            ],
            kickoff: Date()
        )
        #expect(game?.id == "field-id")
        #expect(game?.espnEventId == "espn-id")
    }

    @Test func emptyFieldIdFallsBackToDocumentId() {
        let id = SlateGameDecoding.resolvedId(
            fieldId: "  ",
            documentId: "401671749",
            espnEventId: "other"
        )
        #expect(id == "401671749")
    }

    @Test func mergedSlatePrefersGamesThenFillsFromNominations() {
        let game = SlateGame(
            id: "1",
            espnEventId: "1",
            homeTeamId: "h",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "a",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            spread: 3,
            spreadTeamId: "h",
            kickoff: Date(),
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            winnerTeamId: nil
        )
        let matchingNom = Nomination(
            id: "n1",
            submittedBy: "u",
            submitterName: "Pat",
            espnEventId: "1",
            spread: 10,
            spreadTeamId: "h",
            homeTeamId: "h",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "a",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            kickoff: Date(),
            createdAt: Date()
        )
        let extraNom = Nomination(
            id: "n2",
            submittedBy: "u",
            submitterName: "Pat",
            espnEventId: "2",
            spread: 6.5,
            spreadTeamId: "x",
            homeTeamId: "x",
            homeTeamName: "Texas",
            homeTeamAbbreviation: "TEX",
            homeTeamLogoURL: nil,
            awayTeamId: "y",
            awayTeamName: "Ohio State",
            awayTeamAbbreviation: "OSU",
            awayTeamLogoURL: nil,
            kickoff: Date(),
            createdAt: Date()
        )

        let merged = SlateGameDecoding.mergedSlate(games: [game], nominations: [matchingNom, extraNom])
        #expect(merged.map(\.espnEventId) == ["1", "2"])
        #expect(merged[0].spread == 3)
        #expect(merged[1].spread == 6.5)
    }

    @Test func sortedByKickoffPutsEarliestGameFirst() {
        func game(_ id: String, kickoff: Date) -> SlateGame {
            SlateGame(
                id: id,
                espnEventId: id,
                homeTeamId: "h",
                homeTeamName: "Home",
                homeTeamAbbreviation: "HOM",
                homeTeamLogoURL: nil,
                awayTeamId: "a",
                awayTeamName: "Away",
                awayTeamAbbreviation: "AWY",
                awayTeamLogoURL: nil,
                spread: 3,
                spreadTeamId: "h",
                kickoff: kickoff,
                status: .scheduled,
                homeScore: nil,
                awayScore: nil,
                winnerTeamId: nil
            )
        }
        let late = Date(timeIntervalSince1970: 1_777_200_000)
        let early = Date(timeIntervalSince1970: 1_777_000_000)
        let sorted = [game("late", kickoff: late), game("early", kickoff: early)].sortedByKickoff
        #expect(sorted.map(\.id) == ["early", "late"])
    }

    @Test func missingBroadcastFieldsDefaultSafely() {
        let game = SlateGameDecoding.make(
            documentId: "401856766",
            data: [
                "espnEventId": "401856766",
                "homeTeamName": "TCU",
                "awayTeamName": "North Carolina",
                "spread": 7.5,
                "spreadTeamId": "2628",
                "homeTeamId": "2628",
                "awayTeamId": "153",
            ],
            kickoff: Date()
        )
        #expect(game?.broadcastLabel == nil)
        #expect(game?.isNeutralSite == false)
        #expect(game?.matchupSeparator == "@")
    }

    @Test func broadcastAndNeutralSiteDecode() {
        let game = SlateGameDecoding.make(
            documentId: "401856766",
            data: [
                "espnEventId": "401856766",
                "homeTeamName": "TCU",
                "awayTeamName": "North Carolina",
                "broadcastLabel": "ESPN",
                "isNeutralSite": true,
            ],
            kickoff: Date()
        )
        #expect(game?.broadcastLabel == "ESPN")
        #expect(game?.isNeutralSite == true)
        #expect(game?.matchupSeparator == "vs")
        #expect(game?.kickoffMetaLine.contains("ESPN") == true)
    }

    @Test func mergedSlateUsesNominationsWhenGamesEmpty() {
        let nom = Nomination(
            id: "n1",
            submittedBy: "u",
            submitterName: "Pat",
            espnEventId: "401",
            spread: 4.5,
            spreadTeamId: "h",
            homeTeamId: "h",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "a",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            kickoff: Date(),
            createdAt: Date()
        )
        let merged = SlateGameDecoding.mergedSlate(games: [], nominations: [nom])
        #expect(merged.count == 1)
        #expect(merged[0].id == "401")
        #expect(merged[0].spread == 4.5)
    }

    @Test func spreadRepairRewritesInvertedScheduledFavorite() {
        let stored = game(spread: 5.5, spreadTeamId: "a", status: .scheduled)
        let espn = game(spread: 4, spreadTeamId: "h", status: .scheduled)
        let repair = SlateGameDecoding.spreadRepair(existing: stored, espn: espn)
        #expect(repair?.spread == 4)
        #expect(repair?.spreadTeamId == "h")
    }

    @Test func spreadRepairSkipsLiveAndMatchingRows() {
        let live = game(spread: 5.5, spreadTeamId: "a", status: .inProgress)
        let espn = game(spread: 4, spreadTeamId: "h", status: .scheduled)
        #expect(SlateGameDecoding.spreadRepair(existing: live, espn: espn) == nil)

        let matching = game(spread: 4, spreadTeamId: "h", status: .scheduled)
        #expect(SlateGameDecoding.spreadRepair(existing: matching, espn: espn) == nil)
    }

    @Test func favoriteSpreadDisplayLeadsWithFavoriteAbbreviation() {
        #expect(game(spread: 4, spreadTeamId: "h", status: .scheduled).favoriteSpreadDisplay == "HOM -4.0")
        #expect(game(spread: 5.5, spreadTeamId: "a", status: .scheduled).favoriteSpreadDisplay == "AWY -5.5")
    }

    private func game(spread: Double, spreadTeamId: String, status: SlateGame.GameStatus) -> SlateGame {
        SlateGame(
            id: "401",
            espnEventId: "401",
            homeTeamId: "h",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "a",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            spread: spread,
            spreadTeamId: spreadTeamId,
            kickoff: Date(),
            status: status,
            homeScore: nil,
            awayScore: nil,
            winnerTeamId: nil
        )
    }
}

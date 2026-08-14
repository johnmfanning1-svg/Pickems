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
}

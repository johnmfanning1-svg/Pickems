import Foundation
import Testing
@testable import Pickems

struct SelectionKickoffGateTests {
    private let now = Date(timeIntervalSince1970: 1_759_000_000)

    @Test func kickoffAtOrBeforeNowIsClosed() {
        #expect(SelectionKickoffGate.hasKickedOff(kickoff: now, now: now))
        #expect(SelectionKickoffGate.hasKickedOff(kickoff: now.addingTimeInterval(-1), now: now))
        #expect(!SelectionKickoffGate.hasKickedOff(kickoff: now.addingTimeInterval(1), now: now))
    }

    @Test func inProgressOrFinalIsClosedEvenBeforeKickoff() {
        let later = now.addingTimeInterval(60 * 60)
        #expect(SelectionKickoffGate.hasKickedOff(kickoff: later, status: .inProgress, now: now))
        #expect(SelectionKickoffGate.hasKickedOff(kickoff: later, status: .final, now: now))
        #expect(!SelectionKickoffGate.hasKickedOff(kickoff: later, status: .scheduled, now: now))
    }

    @Test func espnGameUsesKickoffAndStatus() {
        let open = game(kickoff: now.addingTimeInterval(60), status: .scheduled)
        let started = game(kickoff: now.addingTimeInterval(60), status: .inProgress)
        let played = game(kickoff: now.addingTimeInterval(-60), status: .scheduled)
        #expect(!SelectionKickoffGate.hasKickedOff(open, now: now))
        #expect(SelectionKickoffGate.hasKickedOff(started, now: now))
        #expect(SelectionKickoffGate.hasKickedOff(played, now: now))
    }

    @Test func rejectionMessageNamesTheMatchup() {
        #expect(
            SelectionKickoffGate.rejectionMessage(matchups: ["JVST @ KENN"])
                == "JVST @ KENN has already kicked off and can't be added to Selections."
        )
        #expect(
            SelectionKickoffGate.rejectionMessage(matchups: ["JVST @ KENN", "ALA @ UGA"])
                == "JVST @ KENN and ALA @ UGA have already kicked off and can't be added to Selections."
        )
        #expect(
            SelectionKickoffGate.rejectionMessage(matchups: [])
                == "That game has already kicked off and can't be added to Selections."
        )
    }

    private func game(kickoff: Date, status: SlateGame.GameStatus) -> ESPNGame {
        ESPNGame(
            id: "401",
            espnEventId: "401",
            competitionId: "401",
            homeTeamId: "h",
            homeTeamName: "Kennesaw St",
            homeTeamAbbreviation: "KENN",
            homeTeamLogoURL: nil,
            awayTeamId: "a",
            awayTeamName: "Jacksonville St",
            awayTeamAbbreviation: "JVST",
            awayTeamLogoURL: nil,
            kickoff: kickoff,
            spread: nil,
            spreadTeamId: nil,
            status: status,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: nil,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil
        )
    }
}

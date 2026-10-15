import Foundation
import Testing
@testable import Pickems

struct ScheduledGameEligibilityTests {
    @Test func disruptionLabelExcludesUpcomingSelectionAndPicks() {
        let labels = ["Postponed", "Canceled", "Suspended", "Delayed"]
        let names = ["STATUS_POSTPONED", "STATUS_CANCELED", "STATUS_SUSPENDED", "STATUS_DELAYED"]
        for (name, label) in zip(names, labels) {
            let resolved = ESPNService.resolvedSlateStatus(
                name: name,
                state: "post",
                completed: true,
                shortDetail: label,
                detail: label
            )
            #expect(resolved.status == .scheduled)
            #expect(resolved.label == label)
            #expect(!ScheduledGameEligibility.isUpcoming(status: resolved.status, statusLabel: resolved.label))
            #expect(!ScheduledGameEligibility.canSelectOrPick(statusLabel: resolved.label))
            #expect(ScheduledGameEligibility.hasDisruptionLabel(label))
        }

        let open = ESPNService.resolvedSlateStatus(
            name: "STATUS_SCHEDULED",
            state: "pre",
            completed: false,
            shortDetail: "Sat 3:30 PM",
            detail: nil
        )
        #expect(open.status == .scheduled)
        #expect(ScheduledGameEligibility.isUpcoming(status: open.status, statusLabel: open.label))
        #expect(ScheduledGameEligibility.canSelectOrPick(statusLabel: open.label))
        #expect(!ScheduledGameEligibility.hasDisruptionLabel(nil))
        #expect(!ScheduledGameEligibility.hasDisruptionLabel("  "))
        #expect(!ScheduledGameEligibility.hasDisruptionLabel("Final"))
        #expect(!ScheduledGameEligibility.isUpcoming(status: .inProgress, statusLabel: nil))
        #expect(!ScheduledGameEligibility.isUpcoming(status: .final, statusLabel: nil))
        #expect(ScheduledGameEligibility.canSelectOrPick(statusLabel: nil))
    }

    @Test func scheduledImportDropsFutureDisruptedGames() {
        let games = [
            game(id: "postponed", status: .scheduled, statusLabel: "Postponed"),
            game(id: "open", status: .scheduled, statusLabel: nil),
            game(id: "canceled", status: .scheduled, statusLabel: "Canceled"),
            game(id: "live", status: .inProgress, statusLabel: nil),
            game(id: "final", status: .final, statusLabel: nil),
            game(id: "suspended", status: .scheduled, statusLabel: "Suspended"),
            game(id: "delayed", status: .scheduled, statusLabel: "Delayed")
        ]
        let imported = ScheduledGameEligibility.gamesEligibleForScheduledImport(games)
        #expect(imported.map(\.id) == ["open"])
    }

    @Test func liveScoreboardLabelWinsOverStaleBrowseLabel() {
        let cleared = ScheduledGameEligibility.resolvedStatusLabel(
            liveCardPresent: true,
            liveLabel: nil,
            espnLabel: "Delayed"
        )
        #expect(ScheduledGameEligibility.canSelectOrPick(statusLabel: cleared))

        let stillDelayed = ScheduledGameEligibility.resolvedStatusLabel(
            liveCardPresent: true,
            liveLabel: "Delayed",
            espnLabel: nil
        )
        #expect(!ScheduledGameEligibility.canSelectOrPick(statusLabel: stillDelayed))

        let browseOnly = ScheduledGameEligibility.resolvedStatusLabel(
            liveCardPresent: false,
            liveLabel: nil,
            espnLabel: "Canceled"
        )
        #expect(!ScheduledGameEligibility.isUpcoming(status: .scheduled, statusLabel: browseOnly))
    }

    @Test func rejectionMessageNamesTheDisruption() {
        let canceled = game(id: "canceled", status: .scheduled, statusLabel: "Canceled")
        #expect(
            ScheduledGameEligibility.rejectionMessage(for: [canceled])
                == "AUB @ UGA is canceled and can't be selected or picked."
        )
        #expect(ScheduledGameEligibility.selectionRejectionMessage(for: [canceled]) != nil)

        let open = game(id: "open", status: .scheduled, statusLabel: nil)
        #expect(ScheduledGameEligibility.selectionRejectionMessage(for: [open]) == nil)

        let postponed = game(id: "postponed", status: .scheduled, statusLabel: "Postponed")
        #expect(
            ScheduledGameEligibility.rejectionMessage(for: [canceled, postponed])
                == "AUB @ UGA is canceled and AUB @ UGA is postponed and can't be selected or picked."
        )
    }

    @Test func requiredPicksSkipDisruptedGames() {
        let slate = ["open-early", "canceled", "open-late"]
        let required = ScheduledGameEligibility.requiredPickIds(
            slateGameIds: slate,
            ineligibleGameIds: ["canceled"]
        )
        #expect(required == ["open-early", "open-late"])
        #expect(ScheduledGameEligibility.picksCover(
            requiredGameIds: required,
            pickedGameIds: ["open-early", "open-late"]
        ))
        #expect(ScheduledGameEligibility.picksCover(
            requiredGameIds: required,
            pickedGameIds: ["open-early", "canceled", "open-late"]
        ))
        #expect(!ScheduledGameEligibility.picksCover(
            requiredGameIds: required,
            pickedGameIds: ["open-early", "canceled"]
        ))

        let allRequired = ScheduledGameEligibility.requiredPickIds(
            slateGameIds: slate,
            ineligibleGameIds: []
        )
        #expect(allRequired == Set(slate))
        #expect(!ScheduledGameEligibility.picksCover(
            requiredGameIds: allRequired,
            pickedGameIds: ["open-early", "open-late"]
        ))
    }

    private func game(
        id: String,
        status: SlateGame.GameStatus,
        statusLabel: String?
    ) -> ESPNGame {
        ESPNGame(
            id: id,
            espnEventId: id,
            competitionId: id,
            homeTeamId: "61",
            homeTeamName: "Georgia Bulldogs",
            homeTeamAbbreviation: "UGA",
            homeTeamLogoURL: nil,
            awayTeamId: "2",
            awayTeamName: "Auburn Tigers",
            awayTeamAbbreviation: "AUB",
            awayTeamLogoURL: nil,
            kickoff: Date(timeIntervalSince1970: 1_800_000_000),
            spread: nil,
            spreadTeamId: nil,
            status: status,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: nil,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil,
            statusLabel: statusLabel
        )
    }
}

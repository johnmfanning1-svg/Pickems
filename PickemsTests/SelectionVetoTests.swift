import Foundation
import Testing
@testable import Pickems

struct SelectionVetoTests {
    private let now = Date(timeIntervalSince1970: 1_759_000_000)

    @Test func vetoDefaultsOffAndNeedsTwoVotes() {
        let rules = GroupRules.default
        #expect(rules.vetoEnabled == false)
        #expect(rules.vetoVotesNeeded == 2)
        #expect(SelectionVetoPolicy.defaultVotesNeeded == 2)
    }

    @Test func missingStoredFieldsStayOff() throws {
        let json = """
        {
          "selectionMode": "member",
          "selectionsPerMember": 3,
          "slateSize": 12,
          "pickDeadline": "firstKickoff",
          "tieBreaker": "commissionerOverride"
        }
        """.data(using: .utf8)!
        let rules = try JSONDecoder().decode(GroupRules.self, from: json)
        #expect(rules.vetoEnabled == false)
        #expect(rules.vetoVotesNeeded == 2)
    }

    @Test func votesNeededCapsAtOneLessThanLeagueSize() {
        #expect(SelectionVetoPolicy.maxVotesNeeded(memberCount: 1) == 0)
        #expect(SelectionVetoPolicy.maxVotesNeeded(memberCount: 5) == 4)
        #expect(!SelectionVetoPolicy.canConfigure(memberCount: 1))
        #expect(SelectionVetoPolicy.canConfigure(memberCount: 2))
        #expect(SelectionVetoPolicy.clampedVotesNeeded(2, memberCount: 8) == 2)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(9, memberCount: 4) == 3)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(2, memberCount: 2) == 1)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(0, memberCount: 6) == 2)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(4, memberCount: 1) == 4)
    }

    @Test func onlyAnotherMemberCanVoteWhileSelectionsAreOpen() {
        let kickoff = now.addingTimeInterval(60 * 60)
        #expect(
            SelectionVetoPolicy.canVote(
                vetoEnabled: true,
                isOwnSelection: false,
                selectionsOpen: true,
                kickoff: kickoff,
                now: now
            )
        )
        #expect(
            !SelectionVetoPolicy.canVote(
                vetoEnabled: false,
                isOwnSelection: false,
                selectionsOpen: true,
                kickoff: kickoff,
                now: now
            )
        )
        #expect(
            !SelectionVetoPolicy.canVote(
                vetoEnabled: true,
                isOwnSelection: true,
                selectionsOpen: true,
                kickoff: kickoff,
                now: now
            )
        )
        #expect(
            !SelectionVetoPolicy.canVote(
                vetoEnabled: true,
                isOwnSelection: false,
                selectionsOpen: false,
                kickoff: kickoff,
                now: now
            )
        )
        #expect(
            !SelectionVetoPolicy.canVote(
                vetoEnabled: true,
                isOwnSelection: false,
                selectionsOpen: true,
                kickoff: now,
                now: now
            )
        )
    }

    @Test func aVetoBlocksThatMemberFromTheSameGame() {
        let veto = SelectionVeto(
            id: "selector_401",
            submittedBy: "selector",
            submitterName: "Sam",
            espnEventId: "401",
            awayTeamName: "Alabama",
            awayTeamAbbreviation: "ALA",
            homeTeamName: "Georgia",
            homeTeamAbbreviation: "UGA",
            voteCount: 2,
            votesNeeded: 2
        )
        #expect(SelectionVetoPolicy.blockedEventIds(vetoes: [veto], userId: "selector") == ["401"])
        #expect(SelectionVetoPolicy.blockedEventIds(vetoes: [veto], userId: "other").isEmpty)
        #expect(veto.matchupLabel == "ALA @ UGA")
    }

    @Test func settingsFooterNamesTheCap() {
        #expect(SelectionVetoPolicy.settingsFooter(memberCount: 4).contains("3"))
        #expect(SelectionVetoPolicy.settingsFooter(memberCount: 1).contains("other member"))
    }

    @Test func selectionVetoPushOpensThatGame() {
        let action = DeepLinkRouter.parseNotification(userInfo: [
            "type": "selection_veto",
            "groupId": "group-1",
            "weekId": "2026-W6",
            "gameId": "401",
            "deepLink": "pickems://league/group-1/week/2026-W6/game/401",
        ])
        #expect(action == .openGame(groupId: "group-1", weekId: "2026-W6", gameId: "401"))
        #expect(
            NotificationLaunch.resolve(
                action: action!,
                groupsLoaded: true,
                memberGroupIds: ["group-1"]
            ) == .pickems(groupId: "group-1", weekId: "2026-W6", gameId: "401")
        )
    }

    @Test func selectionVetoUsesTheSelectionDeadlinePreference() {
        #expect(NotificationPrefCategory.selectionDeadlines.pushTypes.contains("selection_veto"))
        let others = NotificationPrefCategory.allCases.filter { $0 != .selectionDeadlines }
        #expect(others.allSatisfy { !$0.pushTypes.contains("selection_veto") })
    }
}

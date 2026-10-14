import Foundation
import Testing
@testable import Pickems

struct SelectionVetoTests {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func week(_ status: WeekStatus = .selection, deadline: Date? = nil) -> WeekSummary {
        WeekSummary(
            id: "2026-W8", seasonYear: 2026, weekNumber: 8, status: status,
            slateSize: 6, selectionMode: .member, selectionsPerMember: 2,
            lockedAt: nil, pickDeadline: nil, nominationCount: 3,
            selectionDeadline: deadline ?? now.addingTimeInterval(3600)
        )
    }

    private func nomination(kickoff: Date? = nil) -> Nomination {
        Nomination(
            id: "n1", submittedBy: "sel", submitterName: "Sam", espnEventId: "401",
            spread: 3.5, spreadTeamId: "h", homeTeamId: "h", homeTeamName: "Alabama",
            homeTeamAbbreviation: "BAMA", homeTeamLogoURL: nil, awayTeamId: "a",
            awayTeamName: "Georgia", awayTeamAbbreviation: "UGA", awayTeamLogoURL: nil,
            kickoff: kickoff ?? now.addingTimeInterval(7200), createdAt: now
        )
    }

    private var vetoRules: GroupRules {
        var rules = GroupRules.default
        rules.allowVeto = true
        return rules
    }

    private let members = ["sel", "a", "b", "c"]

    @Test func vetoIsOffByDefaultWithTwoVotes() throws {
        #expect(GroupRules.default.allowVeto == false)
        #expect(GroupRules.default.vetoVotesNeeded == 2)
        let json = #"{"selectionMode":"member","selectionsPerMember":2,"slateSize":12,"pickDeadline":"firstKickoff","tieBreaker":"headToHead"}"#
        let decoded = try JSONDecoder().decode(GroupRules.self, from: Data(json.utf8))
        #expect(decoded.allowVeto == false)
        #expect(decoded.vetoVotesNeeded == 2)
    }

    @Test func thresholdCapsAtLeagueSizeMinusOne() {
        var rules = vetoRules
        rules.vetoVotesNeeded = 9
        #expect(rules.vetoThreshold(memberCount: 4) == 3)
        #expect(GroupRules.maxVetoVotesNeeded(memberCount: 4) == 3)
        #expect(GroupRules.maxVetoVotesNeeded(memberCount: 1) == 1)
        rules.vetoVotesNeeded = 0
        #expect(rules.vetoThreshold(memberCount: 4) == 1)
    }

    @Test func onlyOtherMembersCanVoteWhileSelectionsOpenBeforeKickoff() {
        let nom = nomination()
        #expect(SelectionVeto.canVote(rules: vetoRules, week: week(), nomination: nom, voterId: "a", memberIds: members, now: now))
        #expect(!SelectionVeto.canVote(rules: vetoRules, week: week(), nomination: nom, voterId: "sel", memberIds: members, now: now))
        #expect(!SelectionVeto.canVote(rules: vetoRules, week: week(), nomination: nom, voterId: "outsider", memberIds: members, now: now))
        #expect(!SelectionVeto.canVote(rules: .default, week: week(), nomination: nom, voterId: "a", memberIds: members, now: now))
        #expect(!SelectionVeto.canVote(rules: vetoRules, week: week(.picking), nomination: nom, voterId: "a", memberIds: members, now: now))
        #expect(!SelectionVeto.canVote(rules: vetoRules, week: week(deadline: now.addingTimeInterval(-1)), nomination: nom, voterId: "a", memberIds: members, now: now))
        #expect(!SelectionVeto.canVote(rules: vetoRules, week: week(), nomination: nomination(kickoff: now.addingTimeInterval(-1)), voterId: "a", memberIds: members, now: now))
    }

    @Test func progressShowsServerCounts() {
        var nom = nomination()
        #expect(SelectionVeto.progressText(nom, rules: vetoRules, memberCount: 4) == nil)
        nom.vetoVoteCount = 1
        nom.vetoVotesNeeded = 3
        #expect(SelectionVeto.progressText(nom, rules: vetoRules, memberCount: 4) == "Veto votes 1/3")
    }

    @Test func vetoPushOpensThatGameInThatLeague() {
        let action = DeepLinkRouter.parseNotification(userInfo: [
            "type": "selection_veto", "groupId": "g1", "weekId": "2026-W8", "gameId": "401",
        ])
        #expect(action == .openGame(groupId: "g1", weekId: "2026-W8", gameId: "401"))
        let viaLink = DeepLinkRouter.parseNotification(userInfo: [
            "type": "selection_veto", "deepLink": "pickems://league/g1/week/2026-W8/game/401",
        ])
        #expect(viaLink == .openGame(groupId: "g1", weekId: "2026-W8", gameId: "401"))
        #expect(NotificationPrefCategory.selectionDeadlines.pushTypes.contains("selection_veto"))
    }
}

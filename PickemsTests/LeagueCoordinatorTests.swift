import Foundation
import Testing
@testable import Pickems

struct LeagueCoordinatorTests {
    @Test func missingCoordinatorsStayAMember() {
        let group = makeGroup(coordinators: nil)
        #expect(LeagueRolePolicy.role(of: "member", in: group) == .member)
        #expect(!LeagueRolePolicy.role(of: "member", in: group).canOperateWeek)
        #expect(LeagueRolePolicy.role(of: "comm", in: group).canOperateWeek)
        #expect(group.coordinatorRole(for: "member") == nil)
    }

    @Test func commissionerIdentityWinsOverAStaleSeat() {
        let group = makeGroup(coordinators: LeagueCoordinators(oc: "comm", dc: "member"))
        #expect(LeagueRolePolicy.role(of: "comm", in: group) == .commissioner)
        #expect(LeagueRolePolicy.activeRole(of: "comm", in: group) == nil)
        #expect(LeagueRolePolicy.activeCoordinators(in: group) == LeagueCoordinators(dc: "member"))
        #expect(group.coordinatorRole(for: "comm") == nil)
        #expect(group.coordinatorRole(for: "member") == .dc)
    }

    @Test func activeSeatsResolveToOcAndDc() {
        let group = makeGroup(coordinators: LeagueCoordinators(oc: "member", dc: "other"))
        #expect(LeagueRolePolicy.role(of: "member", in: group) == .coordinator(.oc))
        #expect(LeagueRolePolicy.role(of: "other", in: group) == .coordinator(.dc))
        #expect(LeagueCoordinatorRole.oc.shortTitle == "OC")
        #expect(LeagueCoordinatorRole.dc.title == "Defensive Coordinator")
        let duplicate = LeagueCoordinators(oc: "member", dc: "member")
            .normalized(memberIds: group.memberIds, commissionerId: group.commissionerId)
        #expect(duplicate == LeagueCoordinators(oc: "member"))
    }

    @Test func nonMemberSeatDoesNotGrantTheRole() {
        let group = makeGroup(coordinators: LeagueCoordinators(oc: "gone", dc: "other"))
        #expect(LeagueRolePolicy.role(of: "gone", in: group) == .member)
        #expect(LeagueRolePolicy.activeRole(of: "gone", in: group) == nil)
        #expect(LeagueRolePolicy.activeCoordinators(in: group).oc == nil)
        #expect(LeagueRolePolicy.activeCoordinators(in: group).dc == "other")
    }

    @Test func assignRejectsTheCommissionerAndOutsiders() throws {
        let group = makeGroup(coordinators: nil)
        #expect(throws: LeagueCoordinatorAssignmentError.isCommissioner) {
            try LeagueRolePolicy.assign(.oc, userId: "comm", group: group)
        }
        #expect(throws: LeagueCoordinatorAssignmentError.notAMember) {
            try LeagueRolePolicy.assign(.dc, userId: "gone", group: group)
        }
        let appointed = try LeagueRolePolicy.assign(.oc, userId: "member", group: group)
        #expect(appointed == LeagueCoordinators(oc: "member"))
    }

    @Test func appointReplacesAndAMoveClearsTheOtherSeat() throws {
        let group = makeGroup(coordinators: LeagueCoordinators(oc: "member", dc: "other"))
        let replaced = try LeagueRolePolicy.assign(.oc, userId: "third", group: group)
        #expect(replaced == LeagueCoordinators(oc: "third", dc: "other"))
        let moved = try LeagueRolePolicy.assign(.dc, userId: "third", group: replacedGroup(replaced))
        #expect(moved == LeagueCoordinators(dc: "third"))
    }

    @Test func clearingOneSeatLeavesTheOther() throws {
        let group = makeGroup(coordinators: LeagueCoordinators(oc: "member", dc: "other"))
        let cleared = try LeagueRolePolicy.assign(.oc, userId: nil, group: group)
        #expect(cleared == LeagueCoordinators(dc: "other"))
        #expect(LeagueRolePolicy.clearing("other", group: replacedGroup(cleared)).isEmpty)
    }

    @Test func mapWriteSkipsDeletesOrReplaces() {
        let current = LeagueCoordinators(oc: "member", dc: "other")
        #expect(LeagueRolePolicy.mapWrite(from: current, to: current) == .unchanged)
        #expect(LeagueRolePolicy.mapWrite(from: nil, to: LeagueCoordinators()) == .unchanged)
        #expect(LeagueRolePolicy.mapWrite(from: current, to: LeagueCoordinators()) == .deleteField)
        #expect(
            LeagueRolePolicy.mapWrite(from: nil, to: LeagueCoordinators(dc: "other"))
                == .replace(oc: nil, dc: "other")
        )
    }

    @Test func permissionMatrix() {
        let commissioner = LeagueActorRole.commissioner.permissions
        let coordinator = LeagueActorRole.coordinator(.oc).permissions
        let member = LeagueActorRole.member.permissions

        #expect(commissioner.operateWeek && coordinator.operateWeek && !member.operateWeek)
        #expect(commissioner.appointCoordinators && !coordinator.appointCoordinators && !member.appointCoordinators)
        #expect(commissioner.editLeagueRules && !coordinator.editLeagueRules)
        #expect(commissioner.changeScoringMode && !coordinator.changeScoringMode)
        #expect(commissioner.removeMembers && !coordinator.removeMembers)
        #expect(commissioner.deleteLeague && !coordinator.deleteLeague && !member.deleteLeague)
        #expect(commissioner.transferCommissioner && !coordinator.transferCommissioner)
        #expect(commissioner.billingOrOwnership && !coordinator.billingOrOwnership && !member.billingOrOwnership)
    }

    @Test func coordinatorOnACommissionerSlateMakesSelections() {
        let waiting = HomeCTAResolver.resolve(
            week: selectionWeek(mode: .commissioner),
            isCommissioner: false,
            didSubmitNominations: false,
            userNominationCount: 0,
            pickCount: 0,
            slateCount: 0,
            pickemsLocked: false,
            picksSubmitted: false
        )
        let operating = HomeCTAResolver.resolve(
            week: selectionWeek(mode: .commissioner),
            isCommissioner: true,
            didSubmitNominations: false,
            userNominationCount: 0,
            pickCount: 0,
            slateCount: 0,
            pickemsLocked: false,
            picksSubmitted: false
        )
        #expect(waiting == .waitingOnSelections)
        #expect(operating == .makeSelections)
        #expect(operating.destinationTab == .selections)
    }

    @Test func leagueWithoutTheKeyDecodesAsNoCoordinators() throws {
        let group = makeGroup(coordinators: LeagueCoordinators(oc: "member"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var object = try JSONSerialization.jsonObject(with: encoder.encode(group)) as! [String: Any]
        object.removeValue(forKey: "coordinators")
        let decoded = try decode(object)
        #expect(decoded.coordinators == nil)
        #expect(LeagueRolePolicy.role(of: "member", in: decoded) == .member)
    }

    @Test func candidatesOmitTheCommissionerAndCurrentHolder() {
        let group = makeGroup(coordinators: LeagueCoordinators(oc: "member", dc: "other"))
        let members = [
            person("comm", "Commish"),
            person("member", "Zed"),
            person("other", "amy"),
            person("third", "Bea"),
            person("gone", "Ghost"),
        ]
        let names = LeagueRolePolicy.candidates(for: .oc, group: group, members: members).map(\.displayName)
        #expect(names == ["amy", "Bea"])
    }

    @Test func badSlotDecodesEmpty() throws {
        let group = makeGroup(coordinators: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var object = try JSONSerialization.jsonObject(with: encoder.encode(group)) as! [String: Any]
        object["coordinators"] = ["oc": 12, "dc": "   ", "extra": "nope"]
        let decoded = try decode(object)
        #expect(decoded.coordinators == LeagueCoordinators())
        #expect(decoded.coordinatorRole(for: "member") == nil)
    }

    @Test func transferClearsTheNewCommissionerSeat() {
        let group = makeGroup(coordinators: LeagueCoordinators(oc: "member", dc: "other"))
        let next = LeagueRolePolicy.clearing("member", group: group, commissionerId: "member")
        #expect(next == LeagueCoordinators(dc: "other"))
        let onlySeat = makeGroup(coordinators: LeagueCoordinators(oc: "member"))
        #expect(LeagueRolePolicy.clearing("member", group: onlySeat, commissionerId: "member").isEmpty)
    }

    private func makeGroup(coordinators: LeagueCoordinators?) -> PickemGroup {
        PickemGroup(
            id: "g1",
            name: "Saturday League",
            inviteCode: "ABC123",
            commissionerId: "comm",
            memberIds: ["comm", "member", "other", "third"],
            rules: .default,
            createdAt: Date(timeIntervalSince1970: 0),
            isPublic: false,
            commissionerOnlyInvites: nil,
            coordinators: coordinators
        )
    }

    private func replacedGroup(_ coordinators: LeagueCoordinators) -> PickemGroup {
        makeGroup(coordinators: coordinators.isEmpty ? nil : coordinators)
    }

    private func person(_ id: String, _ name: String) -> GroupMember {
        GroupMember(
            id: id,
            displayName: name,
            avatarColorHex: "#DC2626",
            role: id == "comm" ? .commissioner : .member,
            joinedAt: Date(timeIntervalSince1970: 0),
            seasonWins: 0,
            seasonLosses: 0
        )
    }

    private func selectionWeek(mode: SelectionMode) -> WeekSummary {
        WeekSummary(
            id: "2026-W1",
            seasonYear: 2026,
            weekNumber: 1,
            status: .selection,
            slateSize: 4,
            selectionMode: mode,
            selectionsPerMember: 1,
            pickDeadline: Date(timeIntervalSince1970: 1_800_000_000),
            nominationCount: 0
        )
    }

    private func decode(_ object: [String: Any]) throws -> PickemGroup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(PickemGroup.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

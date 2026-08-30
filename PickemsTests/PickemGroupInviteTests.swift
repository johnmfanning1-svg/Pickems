import Foundation
import Testing
@testable import Pickems

struct PickemGroupInviteTests {
    @Test func commissionerOnlyInvitesDefaultsOff() {
        let group = makeGroup(isPublic: false, commissionerOnlyInvites: nil)
        #expect(group.commissionerOnlyInvites == nil)
        #expect(!group.restrictsMemberInvites)
        #expect(group.canShareInvite(asCommissioner: false))
        #expect(group.canShareInvite(asCommissioner: true))
    }

    @Test func privateLeagueLocksMemberInvitesWhenEnabled() {
        let group = makeGroup(isPublic: false, commissionerOnlyInvites: true)
        #expect(group.restrictsMemberInvites)
        #expect(!group.canShareInvite(asCommissioner: false))
        #expect(group.canShareInvite(asCommissioner: true))
    }

    @Test func publicLeagueNeverLocksMemberInvites() {
        let group = makeGroup(isPublic: true, commissionerOnlyInvites: true)
        #expect(!group.restrictsMemberInvites)
        #expect(group.canShareInvite(asCommissioner: false))
    }

    @Test func missingCommissionerOnlyInvitesDecodesAsOff() throws {
        let group = makeGroup(isPublic: false, commissionerOnlyInvites: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var object = try JSONSerialization.jsonObject(with: encoder.encode(group)) as! [String: Any]
        object.removeValue(forKey: "commissionerOnlyInvites")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(
            PickemGroup.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.commissionerOnlyInvites == nil)
        #expect(!decoded.restrictsMemberInvites)
        #expect(decoded.canShareInvite(asCommissioner: false))
    }

    @Test func enabledFlagRoundTripsThroughJSON() throws {
        let group = makeGroup(isPublic: false, commissionerOnlyInvites: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(PickemGroup.self, from: encoder.encode(group))
        #expect(decoded.commissionerOnlyInvites == true)
        #expect(decoded.restrictsMemberInvites)
    }

    private func makeGroup(
        isPublic: Bool,
        commissionerOnlyInvites: Bool?
    ) -> PickemGroup {
        PickemGroup(
            id: "g1",
            name: "Review League",
            inviteCode: "ABC123",
            commissionerId: "u1",
            memberIds: ["u1"],
            rules: .default,
            createdAt: Date(timeIntervalSince1970: 0),
            isPublic: isPublic,
            commissionerOnlyInvites: commissionerOnlyInvites
        )
    }
}

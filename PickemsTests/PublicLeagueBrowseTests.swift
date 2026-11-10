import Foundation
import Testing
@testable import Pickems

struct PublicLeagueBrowseTests {
    @Test func browseEntryIsLabeledBrowse() {
        #expect(PublicLeagueBrowse.entryTitle == "Browse")
        #expect(PublicLeagueBrowse.navigationTitle == "Browse")
        #expect(PublicLeagueBrowse.accessibilityLabel == "Browse public leagues")
        #expect(PublicLeagueBrowse.accessibilityHint.contains("public"))
        #expect(PublicLeagueBrowse.accessibilityHint.contains("Private"))
        #expect(PublicLeagueBrowse.entryFooter.contains("not listed"))
        #expect(PublicLeagueBrowse.indexCollection == "publicLeagues")
        #expect(PublicLeagueBrowse.indexCollection != "groups")
    }

    @Test func listsPublicLeaguesWithoutANameOrCode() {
        let listed = PublicLeagueBrowse.listings(from: [
            row(id: "small", name: "Zeta", members: 3),
            row(id: "beta", name: "beta", members: 10, isPublic: true),
            row(id: "alpha", name: "Alpha", members: 10),
        ])

        #expect(listed.map(\.groupId) == ["alpha", "beta", "small"])
        #expect(listed.map(\.name) == ["Alpha", "beta", "Zeta"])
        #expect(listed.allSatisfy { $0.isPublic != false })
    }

    @Test func dropsPrivateAndUnjoinableRows() {
        let listed = PublicLeagueBrowse.listings(from: [
            row(id: "public", name: "  Saturday Slate  ", code: "pub123", members: 4),
            row(id: "private", name: "Office Pool", code: "PRIV88", members: 9, isPublic: false),
            row(id: "blank", name: "   ", members: 8),
            row(id: "  ", name: "No Id", members: 8),
            row(id: "bad-code", name: "Bad Code", code: "no", members: 8),
            row(id: "negative", name: "Negative", members: -1),
            row(id: "public", name: "Older Copy", members: 1),
        ])

        #expect(listed.map(\.groupId) == ["public"])
        #expect(listed.first?.name == "Saturday Slate")
        #expect(listed.first?.inviteCode == "PUB123")
        #expect(listed.first?.memberCount == 4)
        #expect(PublicLeagueBrowse.isBrowsable(row(id: "private", isPublic: false)) == false)
    }

    @Test func joinCodeMatchesTheInviteField() {
        let publicLeague = row(id: "public", code: " ab12 ")
        let code = PublicLeagueBrowse.joinCode(for: publicLeague)

        #expect(code == "AB12")
        #expect(InviteCodeRules.isValidFormat(code ?? ""))
        #expect(InviteCodeRules.normalize(publicLeague.inviteCode) == code)
        #expect(PublicLeagueBrowse.joinCode(for: row(id: "private", isPublic: false)) == nil)
        #expect(PublicLeagueBrowse.joinCode(for: row(id: "bad", code: "???1")) == nil)
    }

    @Test func rowCopyDescribesOpenAndJoin() {
        #expect(PublicLeagueBrowse.memberCountLabel(0) == "0 members")
        #expect(PublicLeagueBrowse.memberCountLabel(1) == "1 member")
        #expect(PublicLeagueBrowse.memberCountLabel(12) == "12 members")
        #expect(PublicLeagueBrowse.actionTitle(alreadyMember: false) == "Join")
        #expect(PublicLeagueBrowse.actionTitle(alreadyMember: true) == "Open")
        #expect(PublicLeagueBrowse.actionHint(alreadyMember: false) == "Join this public league")
        #expect(PublicLeagueBrowse.actionHint(alreadyMember: true) == "Open this league")
        #expect(
            PublicLeagueBrowse.rowLabel(name: "Saturday Slate", memberCount: 4, alreadyMember: false)
                == "Saturday Slate, 4 members, Join"
        )
        #expect(
            PublicLeagueBrowse.rowLabel(name: "Saturday Slate", memberCount: 1, alreadyMember: true)
                == "Saturday Slate, 1 member, Open"
        )
    }

    private func row(
        id: String,
        name: String = "Saturday Slate",
        code: String = "PUB123",
        members: Int = 4,
        isPublic: Bool? = nil
    ) -> PublicLeagueListing {
        PublicLeagueListing(
            groupId: id,
            name: name,
            inviteCode: code,
            memberCount: members,
            isPublic: isPublic
        )
    }
}

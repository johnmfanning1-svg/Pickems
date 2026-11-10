import Foundation
import Testing
@testable import Pickems

struct LeagueVisibilityTests {
    @Test func createDefaultsToPrivateAndSkipsTheIndex() {
        #expect(LeagueVisibility.createDefault == .privateLeague)
        #expect(LeagueVisibility.createDefault.isPublic == false)
        #expect(LeagueVisibility.createDefault.title == "Private")
        let order = LeagueVisibility.createWriteOrder(isPublic: false)
        #expect(order == [.groupDocument, .inviteCode, .commissionerMember])
        #expect(!order.contains(.publicIndex))
        #expect(
            LeagueVisibility.browseListingNotice(
                isPublic: false,
                indexRow: nil,
                publishError: StubError()
            ) == nil
        )
    }

    @Test func publicChoiceIndexesAfterTheGroupDocument() {
        #expect(LeagueVisibility.publicLeague.isPublic)
        let order = LeagueVisibility.createWriteOrder(isPublic: true)
        #expect(order == [.groupDocument, .inviteCode, .commissionerMember, .publicIndex])
        #expect(order.first == .groupDocument)
        #expect(order.last == .publicIndex)
    }

    @Test func copyExplainsBrowseVersusInviteOnly() {
        #expect(LeagueVisibility.sectionTitle == "Visibility")
        #expect(LeagueVisibility.sectionDetail.contains("Browse"))
        #expect(LeagueVisibility.sectionDetail.contains("anyone can join"))
        #expect(LeagueVisibility.sectionDetail.contains("invite-only"))
        #expect(LeagueVisibility.privateLeague.detail.contains("Invite-only"))
        #expect(LeagueVisibility.privateLeague.detail.contains("Browse"))
        #expect(LeagueVisibility.publicLeague.detail.contains("Browse"))
        #expect(LeagueVisibility.publicLeague.detail.contains("Anyone can join"))
        #expect(LeagueVisibility.privateLeague.reviewLabel == "Private · invite-only")
        #expect(LeagueVisibility.publicLeague.reviewLabel == "Public · listed in Browse")
        #expect(LeagueVisibility.createdSubtitle(isPublic: false).contains("invite code"))
        #expect(LeagueVisibility.createdSubtitle(isPublic: true).contains("Browse"))
        #expect(LeagueVisibility.allCases.map(\.title) == ["Private", "Public"])
    }

    @Test func settingsToggleAndEmptyStateMatchBrowse() {
        #expect(LeagueVisibility.settingsToggleTitle == "List in Browse")
        #expect(LeagueVisibility.publicSettingsFooter.contains("Browse"))
        #expect(LeagueVisibility.publicSettingsFooter.contains("join"))
        #expect(LeagueVisibility.privateSettingsFooter.contains("invite-only"))
        #expect(LeagueVisibility.privateSettingsFooter.contains("Browse"))
        #expect(PublicLeagueBrowse.emptyMessage.contains("creating"))
        #expect(PublicLeagueBrowse.emptyMessage.contains("league settings"))
        #expect(!PublicLeagueBrowse.emptyMessage.contains("Discover"))
        #expect(LeagueVisibility.listingFailedNotice.contains("List in Browse"))
        #expect(LeagueVisibility.listingRejectedNotice.contains("80"))
    }

    @Test func indexRowAcceptsARulesShapedLeague() {
        let name = String(repeating: "A", count: LeagueVisibility.maxIndexNameLength)
        let row = LeagueVisibility.indexRow(
            groupId: "  league-1  ",
            name: "  \(name)  ",
            inviteCode: " ab12 ",
            memberCount: 0
        )
        #expect(row?.groupId == "league-1")
        #expect(row?.name == name)
        #expect(row?.inviteCode == "AB12")
        #expect(row?.memberCount == 0)
        let fields = row?.storedFields() ?? [:]
        #expect(fields["groupId"] as? String == "league-1")
        #expect(fields["name"] as? String == name)
        #expect(fields["inviteCode"] as? String == "AB12")
        #expect(fields["memberCount"] as? Int == 0)
        #expect(Set(fields.keys).union(["updatedAt"]) == LeagueVisibility.indexFieldNames)
        #expect(LeagueVisibility.indexFieldNames == ["groupId", "name", "inviteCode", "memberCount", "updatedAt"])
    }

    @Test func indexRowRejectsValuesRulesWouldDeny() {
        let tooLong = String(repeating: "B", count: LeagueVisibility.maxIndexNameLength + 1)
        #expect(LeagueVisibility.indexRow(groupId: "g", name: tooLong, inviteCode: "AB12", memberCount: 1) == nil)
        #expect(LeagueVisibility.indexRow(groupId: "g", name: "   ", inviteCode: "AB12", memberCount: 1) == nil)
        #expect(LeagueVisibility.indexRow(groupId: "g", name: "", inviteCode: "AB12", memberCount: 1) == nil)
        #expect(LeagueVisibility.indexRow(groupId: "  ", name: "Saturday", inviteCode: "AB12", memberCount: 1) == nil)
        #expect(LeagueVisibility.indexRow(groupId: "g", name: "Saturday", inviteCode: "AB-12", memberCount: 1) == nil)
        #expect(LeagueVisibility.indexRow(groupId: "g", name: "Saturday", inviteCode: "AB1", memberCount: 1) == nil)
        #expect(LeagueVisibility.indexRow(groupId: "g", name: "Saturday", inviteCode: "ABCDEFGHI", memberCount: 1) == nil)
        #expect(LeagueVisibility.indexRow(groupId: "g", name: "Saturday", inviteCode: "AB12", memberCount: -1) == nil)
        #expect(
            LeagueVisibility.browseListingNotice(isPublic: true, indexRow: nil, publishError: nil)
                == LeagueVisibility.listingRejectedNotice
        )
    }

    @Test @MainActor func publishRetriesUntilTheIndexWriteSucceeds() async {
        #expect(PublicLeagueIndexPublish.maxAttempts == 2)

        let once = PublishCounter()
        let first = await PublicLeagueIndexPublish.attempt {
            await once.record()
        }
        #expect(first == nil)
        #expect(await once.calls == 1)

        let twice = PublishCounter()
        let recovered = await PublicLeagueIndexPublish.attempt {
            let call = await twice.record()
            if call == 1 { throw StubError() }
        }
        #expect(recovered == nil)
        #expect(await twice.calls == 2)
    }

    @Test @MainActor func failedIndexWriteDoesNotAbortCreation() async {
        let counter = PublishCounter()
        let error = await PublicLeagueIndexPublish.attempt {
            await counter.record()
            throw StubError()
        }
        #expect((error as? StubError) == StubError())
        #expect(await counter.calls == PublicLeagueIndexPublish.maxAttempts)

        let row = LeagueVisibility.indexRow(
            groupId: "g",
            name: "Saturday Slate",
            inviteCode: "AB12",
            memberCount: 1
        )
        #expect(
            LeagueVisibility.browseListingNotice(isPublic: true, indexRow: row, publishError: error)
                == LeagueVisibility.listingFailedNotice
        )
        #expect(
            LeagueVisibility.browseListingNotice(isPublic: true, indexRow: row, publishError: nil) == nil
        )
    }
}

private struct StubError: Error, Equatable, Sendable {}

private actor PublishCounter {
    private(set) var calls = 0

    func record() -> Int {
        calls += 1
        return calls
    }
}

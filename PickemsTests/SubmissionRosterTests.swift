import Foundation
import Testing
@testable import Pickems

struct SubmissionRosterTests {
    @Test func sortsNotStartedThenInProgressThenSubmitted() {
        let members = [
            member("c", "Cara"),
            member("a", "Alex"),
            member("b", "Blake"),
        ]
        let submissions = [
            PickSubmission(id: "a", userId: "a", displayName: "Alex", isLocked: true, submittedAt: Date(), pickCount: 8),
            PickSubmission(id: "b", userId: "b", displayName: "Blake", isLocked: false, submittedAt: nil, pickCount: 3),
        ]

        let rows = SubmissionRoster.rows(members: members, submissions: submissions, slateSize: 8)
        #expect(rows.map(\.id) == ["c", "b", "a"])
        #expect(rows.map(\.status) == [.notStarted, .inProgress, .submitted])
        #expect(SubmissionRoster.submittedCount(in: rows) == 1)
    }

    @Test func treatsFullUnlockedSlateAsSubmitted() {
        let members = [member("a", "Alex")]
        let submissions = [
            PickSubmission(id: "a", userId: "a", displayName: "Alex", isLocked: false, submittedAt: nil, pickCount: 8),
        ]
        let rows = SubmissionRoster.rows(members: members, submissions: submissions, slateSize: 8)
        #expect(rows.first?.status == .submitted)
        #expect(rows.first?.made == 8)
    }

    @Test func lockedWithMissingCountAssumesFullSlate() {
        let members = [member("a", "Alex")]
        let submissions = [
            PickSubmission(id: "a", userId: "a", displayName: "Alex", isLocked: true, submittedAt: Date(), pickCount: 0),
        ]
        let rows = SubmissionRoster.rows(members: members, submissions: submissions, slateSize: 6)
        #expect(rows.first?.status == .submitted)
        #expect(rows.first?.made == 6)
    }

    @Test func missingSubmissionIsNotStarted() {
        let members = [member("a", "Alex")]
        let rows = SubmissionRoster.rows(members: members, submissions: [], slateSize: 8)
        #expect(rows.first?.status == .notStarted)
        #expect(rows.first?.made == 0)
        #expect(rows.first?.total == 8)
        #expect(SubmissionRoster.submittedCount(in: rows) == 0)
    }

    @Test func statusUsesCountsAndLock() {
        #expect(SubmissionRoster.status(made: 0, total: 8, isLocked: false) == .notStarted)
        #expect(SubmissionRoster.status(made: 3, total: 8, isLocked: false) == .inProgress)
        #expect(SubmissionRoster.status(made: 8, total: 8, isLocked: false) == .submitted)
        #expect(SubmissionRoster.status(made: 0, total: 8, isLocked: true) == .submitted)
    }

    @Test func selectionProgressCountsNominations() {
        let nominations = [
            nomination(by: "a"),
            nomination(by: "a"),
            nomination(by: "b"),
        ]
        let partial = SubmissionRoster.selectionProgress(
            nominations: nominations,
            memberId: "a",
            perMember: 3
        )
        #expect(partial.made == 2)
        #expect(partial.total == 3)
        #expect(partial.status == .inProgress)

        let none = SubmissionRoster.selectionProgress(
            nominations: nominations,
            memberId: "c",
            perMember: 3
        )
        #expect(none.status == .notStarted)

        let done = SubmissionRoster.selectionProgress(
            nominations: nominations + [nomination(by: "a")],
            memberId: "a",
            perMember: 3
        )
        #expect(done.status == .submitted)
    }

    private func member(_ id: String, _ name: String) -> GroupMember {
        GroupMember(
            id: id,
            displayName: name,
            avatarColorHex: "#111",
            role: .member,
            joinedAt: Date(),
            seasonWins: 0,
            seasonLosses: 0
        )
    }

    private func nomination(by userId: String) -> Nomination {
        Nomination(
            id: UUID().uuidString,
            submittedBy: userId,
            submitterName: "Tester",
            espnEventId: "evt-\(userId)",
            spread: 3.5,
            spreadTeamId: "home",
            homeTeamId: "home",
            homeTeamName: "Home",
            awayTeamId: "away",
            awayTeamName: "Away",
            kickoff: Date(),
            createdAt: Date()
        )
    }
}

import Foundation

enum SubmissionRosterStatus: Equatable {
    case notStarted
    case inProgress
    case submitted

    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .inProgress: return "In progress"
        case .submitted: return "Submitted"
        }
    }
}

struct SubmissionRosterRow: Identifiable, Equatable {
    let id: String
    let displayName: String
    let initials: String
    let avatarColorHex: String
    let avatarImageURL: String?
    let made: Int
    let total: Int
    let status: SubmissionRosterStatus
}

enum SubmissionRoster {
    /// Public counts only — never includes which teams were picked.
    static func rows(
        members: [GroupMember],
        submissions: [PickSubmission],
        slateSize: Int
    ) -> [SubmissionRosterRow] {
        let total = max(slateSize, 0)
        let byUser = Dictionary(uniqueKeysWithValues: submissions.map { ($0.userId, $0) })
        return members
            .map { member in
                let submission = byUser[member.id]
                let made = pickCount(submission, slateSize: total)
                return SubmissionRosterRow(
                    id: member.id,
                    displayName: member.displayName,
                    initials: member.initials,
                    avatarColorHex: member.avatarColorHex,
                    avatarImageURL: member.avatarImageURL,
                    made: made,
                    total: total,
                    status: status(for: submission, made: made, slateSize: total)
                )
            }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return sortRank(lhs.status) < sortRank(rhs.status)
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    static func submittedCount(in rows: [SubmissionRosterRow]) -> Int {
        rows.filter { $0.status == .submitted }.count
    }

    private static func sortRank(_ status: SubmissionRosterStatus) -> Int {
        switch status {
        case .notStarted: return 0
        case .inProgress: return 1
        case .submitted: return 2
        }
    }

    private static func pickCount(_ submission: PickSubmission?, slateSize: Int) -> Int {
        guard let submission else { return 0 }
        if submission.pickCount > 0 { return submission.pickCount }
        if submission.isLocked, slateSize > 0 { return slateSize }
        return 0
    }

    private static func status(
        for submission: PickSubmission?,
        made: Int,
        slateSize: Int
    ) -> SubmissionRosterStatus {
        guard let submission else { return .notStarted }
        if submission.isLocked { return .submitted }
        if slateSize > 0, made >= slateSize { return .submitted }
        if made > 0 { return .inProgress }
        return .notStarted
    }
}

import Foundation

/// Right-side summaries for the condensed rows in Commissioner Settings
/// (Selections, Slate, Members). Pure so the copy is unit tested.
enum CommissionerAdminSummary {
    /// Members who have made all their Selections, e.g. "3/12 in".
    static func selections(memberIds: [String], nominations: [Nomination], perMember: Int) -> String {
        let done: Int = memberIds.filter { (memberId: String) in
            SubmissionRoster.selectionProgress(
                nominations: nominations,
                memberId: memberId,
                perMember: perMember
            ).status == .submitted
        }.count
        return "\(done)/\(memberIds.count) in"
    }

    /// "12 games" / "1 game".
    static func slate(gameCount: Int) -> String {
        "\(gameCount) game\(gameCount == 1 ? "" : "s")"
    }

    /// Everyone in the league, commissioner included.
    static func members(count: Int) -> String {
        "\(max(count, 0))"
    }

    /// Row summary for a deadline that is already set. Nil means prompt mode
    /// ("Set Selection Deadline" / "Set Pickems Deadline") instead of a value row.
    static func deadlineValue(_ date: Date?, locked: Bool = false) -> String? {
        guard let date else { return nil }
        let label = PickDeadlineCalculator.lockTimeLabel(for: date)
        if locked {
            return "Locked · \(label)"
        }
        return label
    }
}

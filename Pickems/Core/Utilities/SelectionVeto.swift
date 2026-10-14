import Foundation

/// Client-side mirror of the veto vote rules. Firestore rules and
/// `onSelectionVetoVote` enforce the same checks server-side.
enum SelectionVeto {
    static func canVote(
        rules: GroupRules,
        week: WeekSummary,
        nomination: Nomination,
        voterId: String?,
        memberIds: [String],
        now: Date = Date()
    ) -> Bool {
        guard rules.allowVeto, let voterId else { return false }
        guard memberIds.contains(voterId), nomination.submittedBy != voterId else { return false }
        guard WeekTransition.canRemakeSelections(week, now: now) else { return false }
        return now < nomination.kickoff
    }

    /// "Veto 1/2" style progress; nil before any vote has been counted.
    static func progressText(_ nomination: Nomination, rules: GroupRules, memberCount: Int) -> String? {
        guard let count = nomination.vetoVoteCount, count > 0 else { return nil }
        let needed = nomination.vetoVotesNeeded ?? rules.vetoThreshold(memberCount: memberCount)
        return "Veto votes \(count)/\(needed)"
    }
}

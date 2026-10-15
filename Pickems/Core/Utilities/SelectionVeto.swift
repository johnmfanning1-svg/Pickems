import Foundation

/// Commissioner veto settings and whether a member may vote on one Selection.
enum SelectionVetoPolicy {
    static let defaultVotesNeeded = 2

    /// One less than the league size. Zero when the selector would be the only voter.
    static func maxVotesNeeded(memberCount: Int) -> Int {
        max(memberCount - 1, 0)
    }

    /// A league of one cannot collect a veto. The toggle stays in settings but does nothing.
    static func canConfigure(memberCount: Int) -> Bool {
        maxVotesNeeded(memberCount: memberCount) >= 1
    }

    /// Stored value brought into 1…(league size − 1). A one-person league keeps a usable
    /// number so the setting still makes sense after the next member joins.
    static func clampedVotesNeeded(_ value: Int, memberCount: Int) -> Int {
        let chosen = value >= 1 ? value : defaultVotesNeeded
        let maxVotes = maxVotesNeeded(memberCount: memberCount)
        guard maxVotes >= 1 else { return chosen }
        return min(max(chosen, 1), maxVotes)
    }

    static func canVote(
        vetoEnabled: Bool,
        isOwnSelection: Bool,
        selectionsOpen: Bool,
        kickoff: Date,
        now: Date = Date()
    ) -> Bool {
        vetoEnabled
            && !isOwnSelection
            && selectionsOpen
            && !SelectionKickoffGate.hasKickedOff(kickoff: kickoff, now: now)
    }

    static func blockedEventIds(vetoes: [SelectionVeto], userId: String) -> Set<String> {
        Set(vetoes.filter { $0.submittedBy == userId }.map(\.espnEventId))
    }

    static func settingsFooter(memberCount: Int) -> String {
        if canConfigure(memberCount: memberCount) {
            let maxVotes = maxVotesNeeded(memberCount: memberCount)
            return "Other members can vote to remove a Selection while Selections are open and before that game kicks off. The person who selected it can't vote. Votes needed is at most \(maxVotes)."
        }
        return "Veto needs at least one other member, so it stays off until someone else joins."
    }
}

/// Copy and identity for the "Veto this Selection?" confirmation.
enum SelectionVetoPrompt {
    static let title = "Veto this Selection?"

    static func message(matchup: String, votesNeeded: Int) -> String {
        "\(matchup) is removed if \(votesNeeded) members vote before kickoff. You can't take this vote back."
    }

    /// One id per Selection. A shared id anchors the popover to the member header.
    static func anchorIdentifier(nominationId: String) -> String {
        "selection-veto-\(nominationId)"
    }
}

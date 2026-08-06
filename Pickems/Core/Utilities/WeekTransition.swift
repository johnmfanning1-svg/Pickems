import Foundation
import FirebaseFirestore

enum WeekTransition {
    /// Builds Firestore fields when a week moves into the picking phase.
    /// Filling the slate sets `pickDeadline` from the earliest kickoff but does **not**
    /// freeze the slate — games stay swappable until that deadline (or commissioner early lock).
    static func toPickingUpdates(
        rules: GroupRules,
        kickoffs: [Date],
        nominationCount: Int? = nil,
        setDeadline: Bool = true,
        lockSlate: Bool = false
    ) -> [String: Any] {
        var updates: [String: Any] = [
            "status": WeekStatus.picking.rawValue
        ]

        if let nominationCount {
            updates[FirestoreField.nominationCount] = nominationCount
        }

        // Product rule: spread picks lock at the earliest slate kickoff.
        if setDeadline || lockSlate, let deadline = kickoffs.min() {
            updates["pickDeadline"] = Timestamp(date: deadline)
        }

        if lockSlate {
            // Audit stamp that the slate was closed by the commissioner.
            // Do not zero pickDeadline — members still need time until first kickoff.
            updates["lockedAt"] = Timestamp(date: Date())
        }

        return updates
    }

    /// Commissioner opens picking early (end nomination) — pick deadline stays first kickoff.
    static func lockEarlyUpdates(rules: GroupRules, kickoffs: [Date]) -> [String: Any] {
        toPickingUpdates(rules: rules, kickoffs: kickoffs, setDeadline: true, lockSlate: true)
    }

    /// Slate games/noms can change during selection, or during picking before the pick deadline.
    /// Past weeks already stamped with a fill-time `lockedAt` stay editable until `pickDeadline`.
    static func isSlateEditable(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .selection:
            return true
        case .picking:
            if let deadline = week.pickDeadline {
                return now < deadline
            }
            return true
        case .locked, .scored:
            return false
        }
    }
}

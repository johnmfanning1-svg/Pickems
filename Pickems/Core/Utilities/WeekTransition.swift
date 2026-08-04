import Foundation
import FirebaseFirestore

enum WeekTransition {
    /// Builds Firestore fields when a week moves into the picking phase.
    /// Filling the slate sets `pickDeadline` from kickoffs but does **not** freeze the slate —
    /// games stay swappable until that deadline (or commissioner early lock).
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

        if setDeadline || lockSlate, let deadline = deadline(for: kickoffs, rules: rules) {
            updates["pickDeadline"] = Timestamp(date: deadline)
        }

        if lockSlate {
            // Freeze immediately: deadline = now so picks + slate edits stop without waiting
            // for the scheduled kickoff. `lockedAt` is the audit stamp.
            updates["pickDeadline"] = Timestamp(date: Date())
            updates["lockedAt"] = Timestamp(date: Date())
        }

        return updates
    }

    /// Commissioner "Lock Slate Early" — freezes slate and picks immediately.
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

    private static func deadline(for kickoffs: [Date], rules: GroupRules) -> Date? {
        PickDeadlineCalculator.compute(
            kickoffs: kickoffs,
            policy: rules.pickDeadline,
            customHour: rules.customDeadlineHour,
            customMinute: rules.customDeadlineMinute
        )
    }
}

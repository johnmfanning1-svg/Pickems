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

    /// Completing Selections never opens Pickems. Only the Selection deadline
    /// (Cloud Function) or commissioner lock-early (`lockEarlyUpdates`) flips status.
    static var opensPickingWhenSlateFills: Bool { false }

    /// Members can add/remove Selections while the week is still in `.selection`
    /// and the Selection deadline has not passed. After lock-early or deadline,
    /// status is `.picking` and Selections are frozen.
    static func canRemakeSelections(_ week: WeekSummary, now: Date = Date()) -> Bool {
        guard week.status == .selection else { return false }
        if let deadline = week.selectionDeadline {
            return now < deadline
        }
        return true
    }

    /// Pickems are available only after the week leaves `.selection`.
    static func arePickemsOpen(_ week: WeekSummary) -> Bool {
        switch week.status {
        case .picking, .locked, .scored: return true
        case .selection: return false
        }
    }

    /// Slate games/noms can change during selection, or during picking before the pick deadline.
    /// Past weeks already stamped with a fill-time `lockedAt` stay editable until `pickDeadline`.
    /// Locked/scored weeks are never editable, even if `pickDeadline` is still in the future.
    static func isSlateEditable(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .selection:
            return canRemakeSelections(week, now: now)
        case .picking:
            if let deadline = week.pickDeadline {
                return now < deadline
            }
            return true
        case .locked, .scored:
            return false
        }
    }

    /// Spread Pickems can be edited while the week is picking and the pick deadline has not passed.
    static func arePicksEditable(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .picking:
            if let deadline = week.pickDeadline {
                return now < deadline
            }
            return true
        case .selection, .locked, .scored:
            return false
        }
    }
}

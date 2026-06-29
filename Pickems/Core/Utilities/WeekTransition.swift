import Foundation
import FirebaseFirestore

enum WeekTransition {
    /// Builds Firestore fields when a week moves into the picking phase.
    static func toPickingUpdates(
        rules: GroupRules,
        kickoffs: [Date],
        nominationCount: Int? = nil,
        lockSlate: Bool = false
    ) -> [String: Any] {
        var updates: [String: Any] = [
            "status": WeekStatus.picking.rawValue
        ]

        if let nominationCount {
            updates[FirestoreField.nominationCount] = nominationCount
        }

        if lockSlate {
            updates["lockedAt"] = Timestamp(date: Date())
            if let deadline = deadline(for: kickoffs, rules: rules) {
                updates["pickDeadline"] = Timestamp(date: deadline)
            }
        }

        return updates
    }

    /// Commissioner early lock — always sets deadline and lockedAt.
    static func lockEarlyUpdates(rules: GroupRules, kickoffs: [Date]) -> [String: Any] {
        toPickingUpdates(rules: rules, kickoffs: kickoffs, lockSlate: true)
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

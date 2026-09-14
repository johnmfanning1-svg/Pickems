import Foundation

/// Result of saving one or more games from the browse sheet.
struct SelectionBrowseSaveResult: Equatable {
    var savedEventIds: [String]
    var collidedEventIds: [String]
    var collidedLabels: [String]

    var savedCount: Int { savedEventIds.count }

    var collisionMessage: String? {
        guard !collidedLabels.isEmpty else { return nil }
        let names = LeagueWeekRecapGenerator.joinNames(collidedLabels)
        let verb = collidedLabels.count == 1 ? "was" : "were"
        if savedCount > 0 {
            return "\(names) \(verb) already taken. Your other Selections were saved."
        }
        let other = collidedLabels.count == 1 ? "a different game" : "different games"
        return "\(names) \(verb) already taken. Pick \(other)."
    }
}

/// Picks which requested games can still be written after a server re-read.
enum SelectionBatchPlanner {
    struct Plan: Equatable {
        var acceptedIds: [String]
        var collidedIds: [String]
        var droppedForLimit: [String]
    }

    static func plan(
        requestedIds: [String],
        takenIds: Set<String>,
        remainingSlots: Int
    ) -> Plan {
        var accepted: [String] = []
        var collided: [String] = []
        var dropped: [String] = []
        var seen = Set<String>()
        let slots = max(remainingSlots, 0)
        for id in requestedIds {
            guard seen.insert(id).inserted else { continue }
            if takenIds.contains(id) {
                collided.append(id)
                continue
            }
            if accepted.count >= slots {
                dropped.append(id)
                continue
            }
            accepted.append(id)
        }
        return Plan(acceptedIds: accepted, collidedIds: collided, droppedForLimit: dropped)
    }
}

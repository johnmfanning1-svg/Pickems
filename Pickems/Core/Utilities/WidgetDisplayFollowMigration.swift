import Foundation

/// One-time move onto Follow current league.
/// A saved pin that matches the open league is cleared. A pin for a different league stays.
/// The flag lives in the app group, next to the pin, and is set once a comparison can run.
enum WidgetDisplayFollowMigration {
    static let completedKey = "widgetDisplayFollowMigrationCompleted"

    struct Decision: Equatable {
        var clearPin: Bool
        var markCompleted: Bool
    }

    static func decision(savedId: String?, selectedGroupId: String?, completed: Bool) -> Decision {
        if completed {
            return Decision(clearPin: false, markCompleted: false)
        }
        guard let selected = nonempty(selectedGroupId) else {
            return Decision(clearPin: false, markCompleted: false)
        }
        let saved = nonempty(savedId)
        let clearPin = saved.map { $0 == selected } ?? false
        return Decision(clearPin: clearPin, markCompleted: true)
    }

    /// Returns true when this call removed the saved pin.
    @discardableResult
    static func apply(selectedGroupId: String?, defaults: UserDefaults) -> Bool {
        let saved = defaults.string(forKey: PickemsAppGroup.displayGroupIdKey)
        let completed = defaults.bool(forKey: completedKey)
        let decision = decision(
            savedId: saved,
            selectedGroupId: selectedGroupId,
            completed: completed
        )
        if decision.clearPin {
            defaults.removeObject(forKey: PickemsAppGroup.displayGroupIdKey)
        }
        if decision.markCompleted {
            defaults.set(true, forKey: completedKey)
        }
        return decision.clearPin
    }

    static func applyIfPossible(selectedGroupId: String?) {
        guard let defaults = PickemsAppGroup.defaults else { return }
        apply(selectedGroupId: selectedGroupId, defaults: defaults)
    }

    private static func nonempty(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return id
    }
}

import Foundation

/// Profile's Home Screen & Live Activity league picker.
/// An empty saved pin selects Follow current league.
enum WidgetDisplayGroupPicker {
    /// Not a league id. Checked before membership so it cannot collide with a pin.
    static let followTag = "__pickems_follow_current_league__"
    static let followLabel = "Follow current league"

    enum Pin: Equatable {
        case clear
        case pin(String)
    }

    /// Tag the picker should display. No saved pin selects Follow, even when a league is open.
    static func selectionTag(savedId: String?) -> String {
        guard let savedId, !savedId.isEmpty else { return followTag }
        return savedId
    }

    /// `nil` when the tag is neither Follow nor a current membership.
    static func pin(for tag: String, memberIds: [String]) -> Pin? {
        if tag == followTag { return .clear }
        guard memberIds.contains(tag) else { return nil }
        return .pin(tag)
    }

    /// Writes the picker choice into the app-group pin. Returns false for an unknown tag.
    @discardableResult
    static func apply(tag: String, memberIds: [String], defaults: UserDefaults) -> Bool {
        switch pin(for: tag, memberIds: memberIds) {
        case .clear:
            defaults.removeObject(forKey: PickemsAppGroup.displayGroupIdKey)
            return true
        case .pin(let id):
            defaults.set(id, forKey: PickemsAppGroup.displayGroupIdKey)
            return true
        case nil:
            return false
        }
    }
}

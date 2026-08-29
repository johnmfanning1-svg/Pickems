import Foundation

/// Picks which league the Home Screen widget and Live Activities should show.
/// Independent of in-app browsing once a display id is saved.
enum WidgetDisplayGroupResolver {
    /// Saved id if still a member → selected group → first membership → nil.
    static func resolve(
        savedId: String?,
        selectedGroupId: String?,
        groupIds: [String]
    ) -> String? {
        let saved = Self.nonEmpty(savedId)
        if let saved, groupIds.contains(saved) {
            return saved
        }
        let selected = Self.nonEmpty(selectedGroupId)
        if let selected, groupIds.contains(selected) {
            return selected
        }
        return groupIds.first
    }

    private static func nonEmpty(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return id
    }
}

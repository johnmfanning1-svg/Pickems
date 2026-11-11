import Foundation

/// Picks which league the Home Screen widget and Live Activities should show.
/// A saved pin wins while that league is still a membership. With no pin, follow
/// the league open in the app, then the first membership.
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

    /// The open league's board is not loaded yet. Keep a snapshot that already
    /// belongs to that league. Fetch when the widget is still showing another
    /// league, or has no snapshot, so Follow does not wait on the week listener.
    static func shouldFetchStandingsWhenBoardMissing(
        displayGroupId: String,
        snapshotGroupId: String?
    ) -> Bool {
        snapshotGroupId != displayGroupId
    }

    private static func nonEmpty(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return id
    }
}

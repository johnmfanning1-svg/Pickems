import Foundation

/// Keeps Commissioner Settings, and every sheet stacked on it, from being
/// recreated when a Firestore snapshot replaces `PickemGroup`.
///
/// `if let group = selectedGroup` made the presenter identity the whole value.
/// The groups listener writes a new value on every tick (member count, rules,
/// metadata). SwiftUI then rebuilt `CommissionerSettingsView`, its `@State`
/// route went back to nil, and UIKit dismissed the deadline, members, slate,
/// and spread sheets. The pin is the league id captured for this presentation.
enum CommissionerSheetStability {
    /// League id that owns the open Settings presentation.
    ///
    /// A pin wins over the live selection so a nil flicker or a league switch
    /// cannot retarget Settings that are already on screen. The first frame,
    /// before anything is pinned, uses the live id.
    static func presenterGroupId(liveGroupId: String?, retainedGroupId: String?) -> String? {
        if let retainedGroupId { return retainedGroupId }
        return liveGroupId
    }

    /// Nested sheet route after the presenter league id changes.
    ///
    /// The same id keeps the route. A different league drops it so an editor
    /// cannot save against the wrong league. `previousGroupId == nil` is the
    /// first observation and must not clear a route that was just set.
    static func routeAfterGroupRefresh<Route>(
        route: Route?,
        previousGroupId: String?,
        groupId: String?
    ) -> Route? {
        guard let previousGroupId else { return route }
        guard let groupId, previousGroupId == groupId else { return nil }
        return route
    }

    /// Stand-in league when Settings are open and every live copy of that id
    /// is missing for a frame. The id is what keeps the presenter alive.
    static func placeholderGroup(id: String) -> PickemGroup {
        PickemGroup(
            id: id,
            name: "League",
            inviteCode: "",
            commissionerId: "",
            memberIds: [],
            rules: .default,
            createdAt: .distantPast
        )
    }
}

/// Spread editor content while the slate listener replaces `SlateGame` values.
enum SlateSpreadPresentation {
    /// The live game wins when it is still on the slate. Otherwise the game
    /// captured at tap stays, so the editor is not torn down for a refresh.
    static func game(captured: SlateGame, liveGames: [SlateGame]) -> SlateGame {
        liveGames.first { $0.id == captured.id } ?? captured
    }
}

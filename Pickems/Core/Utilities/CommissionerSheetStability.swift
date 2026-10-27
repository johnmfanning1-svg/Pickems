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
    /// The live game wins when it is still on this league's slate. A slate that
    /// belongs to another league is ignored — week and game ids are shared.
    /// Otherwise the game captured at tap stays.
    static func game(captured: SlateGame, liveGames: [SlateGame], liveBelongsToLeague: Bool) -> SlateGame {
        guard liveBelongsToLeague else { return captured }
        return liveGames.first { $0.id == captured.id } ?? captured
    }
}

/// Commissioner Settings reads and writes for one league, the one the sheet
/// was opened on. Week ids (`2026-W7`) are the same in every league.
enum CommissionerPinnedLeague {
    /// Close Settings when the member is looking at a different league.
    /// A nil live id is a listener flicker and must leave Settings up.
    static func shouldDismiss(settingsOpen: Bool, pinnedGroupId: String?, liveGroupId: String?) -> Bool {
        guard settingsOpen, let pinnedGroupId, let liveGroupId else { return false }
        return pinnedGroupId != liveGroupId
    }

    /// The pinned league from the copies we still have. Never the live
    /// selection when that selection is a different league.
    static func group(
        id pinnedGroupId: String,
        selected: PickemGroup?,
        listed: [PickemGroup],
        fallback: PickemGroup?
    ) -> PickemGroup? {
        if let selected, selected.id == pinnedGroupId { return selected }
        if let listed = listed.first(where: { $0.id == pinnedGroupId }) { return listed }
        if let fallback, fallback.id == pinnedGroupId { return fallback }
        return nil
    }

    /// Live week first, then this league's chip list, then the week captured
    /// at tap. `current` is used only when its observer is still the pin.
    static func week(
        pinnedGroupId: String,
        weekId: String,
        captured: WeekSummary?,
        current: WeekSummary?,
        currentGroupId: String?,
        available: [WeekSummary],
        availableBelongsToPin: Bool
    ) -> WeekSummary? {
        if currentGroupId == pinnedGroupId, let current, current.id == weekId {
            return current
        }
        if availableBelongsToPin, let listed = available.first(where: { $0.id == weekId }) {
            return listed
        }
        if let captured, captured.id == weekId {
            return captured
        }
        return nil
    }

    /// Live slate only while the pick listener is on this league. After a
    /// switch, the games captured at tap stay with the pinned save.
    static func slate(
        pinnedGroupId: String,
        observingGroupId: String?,
        live: [SlateGame],
        captured: [SlateGame]
    ) -> [SlateGame] {
        if observingGroupId == pinnedGroupId { return live }
        return captured
    }
}

/// Spread editor draft versus a later slate snapshot.
enum SpreadDraftRefresh {
    struct Draft: Equatable {
        var spread: Double
        var favoriteIsHome: Bool
        var didEdit: Bool
    }

    /// Unedited drafts follow the server line. An edit the commissioner
    /// already made stays put.
    static func afterServerLine(_ draft: Draft, spread: Double, favoriteIsHome: Bool) -> Draft {
        guard !draft.didEdit else { return draft }
        var next = draft
        next.spread = abs(spread)
        next.favoriteIsHome = favoriteIsHome
        return next
    }

    /// True when the commissioner has edited and the slate line has since moved.
    static func showsLineChangedWarning(draft: Draft, serverSpread: Double, serverFavoriteIsHome: Bool) -> Bool {
        guard draft.didEdit else { return false }
        return draft.spread != abs(serverSpread) || draft.favoriteIsHome != serverFavoriteIsHome
    }
}

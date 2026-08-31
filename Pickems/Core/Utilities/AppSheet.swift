import Foundation

/// App-level modal presented from a single host outside `RootView`.
///
/// SwiftUI dismisses a sheet when its presenter is unmounted or when two views
/// share one `isPresented` flag (Selections + Pickems both wrapped `PicksView`).
/// Route tab CTAs through this enum instead of local `.sheet(isPresented:)`.
///
/// Nested sheets that must stay on top of an already-presented sheet (deadline
/// editors, admin game browse inside Commissioner Settings) stay local — assigning
/// a new `AppSheet` here would replace Settings.
enum AppSheet: Identifiable, Equatable {
    case gameBrowse
    case joinGroup
    case createLeague
    case favoriteTeam(isOnboardingPrompt: Bool)
    case commissionerSettings
    case submissionStatus
    case editProfile
    case deleteAccount
    case stayOnTime
    case coverMoment(gameLabel: String, resultTitle: String, recordText: String, rankText: String)

    var id: String {
        switch self {
        case .gameBrowse: return "gameBrowse"
        case .joinGroup: return "joinGroup"
        case .createLeague: return "createLeague"
        case .favoriteTeam(let onboarding): return "favoriteTeam.\(onboarding)"
        case .commissionerSettings: return "commissionerSettings"
        case .submissionStatus: return "submissionStatus"
        case .editProfile: return "editProfile"
        case .deleteAccount: return "deleteAccount"
        case .stayOnTime: return "stayOnTime"
        case .coverMoment(let game, let result, _, _):
            return "coverMoment.\(game).\(result)"
        }
    }
}

enum AppSheetPresentPolicy: Equatable {
    /// Always show `incoming`, replacing whatever is up.
    case replace
    /// Keep the current sheet; used for deferred prompts (favorite team, notifications).
    case ifIdle
}

enum AppSheetRouting {
    static func nextPresented(
        current: AppSheet?,
        incoming: AppSheet,
        policy: AppSheetPresentPolicy
    ) -> AppSheet? {
        switch policy {
        case .replace:
            return incoming
        case .ifIdle:
            return current ?? incoming
        }
    }
}

/// Event ids already on the slate, minus a game being replaced so it can be re-picked.
enum GameBrowseTakenIds {
    static func make(
        nominationEventIds: [String],
        slateEventIds: [String],
        replacingEventId: String? = nil
    ) -> Set<String> {
        var ids = Set(nominationEventIds)
        ids.formUnion(slateEventIds)
        if let replacingEventId {
            ids.remove(replacingEventId)
        }
        return ids
    }
}

/// End the current touch before mutating presentation state.
/// A ScrollView tap that still has a slight drag is otherwise treated as the
/// new sheet's interactive dismiss (flash of content, then close) on iOS 18/26.
enum PickemsPresentation {
    static func afterTap(_ action: @escaping () -> Void) {
        DispatchQueue.main.async(execute: action)
    }
}

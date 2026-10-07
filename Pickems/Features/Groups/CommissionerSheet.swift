import SwiftUI

/// Every sheet stacked on Commissioner Settings. Presented by ONE `.sheet(item:)` on
/// `CommissionerSettingsView` (outside the Form). Rows inside the Form must never attach
/// `.sheet`/`.alert` — List cells are recycled on every Firestore tick and their presenter
/// dismisses whatever Settings is showing (a401352, #68). See docs/PRESENTATIONS.md.
enum CommissionerSheet: Identifiable, Equatable {
    case selectionDeadline
    case pickDeadline
    case adminGameBrowse
    case members
    case selections
    case slate
    case rankTies(TieRankDraft)

    var id: String {
        switch self {
        case .selectionDeadline:
            return "selectionDeadline"
        case .pickDeadline:
            return "pickDeadline"
        case .adminGameBrowse:
            return "adminGameBrowse"
        case .members:
            return "members"
        case .selections:
            return "selections"
        case .slate:
            return "slate"
        case .rankTies(let draft):
            return "rankTies.\(draft.id)"
        }
    }
}

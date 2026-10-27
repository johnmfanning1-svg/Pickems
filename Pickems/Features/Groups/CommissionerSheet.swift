import SwiftUI

/// Every sheet stacked on Commissioner Settings. Presented by ONE `.sheet(item:)` on
/// `CommissionerSettingsView` (outside the Form). Rows inside the Form must never attach
/// `.sheet`/`.alert` — List cells are recycled on every Firestore tick and their presenter
/// dismisses whatever Settings is showing (a401352, #68). See docs/PRESENTATIONS.md.
///
/// Deadline, Selections, Slate, and tie payloads ride on the case. `id` stays stable
/// so a later week-field change does not dismiss the sheet. Sheet content must read
/// the case, not a second `@State` or `currentWeek` (3.6.6 showed "No Active Week"
/// because that sibling was still nil when `sheet(item:)` presented).
enum CommissionerSheet: Identifiable, Equatable {
    case selectionDeadline(SelectionDeadlineEdit)
    case pickDeadline(PickDeadlineEdit)
    case adminGameBrowse(WeekSummary)
    case members
    case selections(WeekSummary)
    case slate(WeekSummary)
    case rankTies(TieRankDraft, DeadlineEditCapture)

    var id: String {
        switch self {
        case .selectionDeadline(_):
            return "selectionDeadline"
        case .pickDeadline(_):
            return "pickDeadline"
        case .adminGameBrowse(_):
            return "adminGameBrowse"
        case .members:
            return "members"
        case .selections(_):
            return "selections"
        case .slate(_):
            return "slate"
        case .rankTies(let draft, _):
            return "rankTies.\(draft.id)"
        }
    }
}

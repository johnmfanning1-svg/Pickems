import Foundation

/// Single Home hero action. Selections and Pickems never share a CTA.
enum HomeCTA: Equatable {
    case makeSelections
    case editSelections
    case waitingOnSelections
    case makePickems
    case finishPickems
    case submitPickems
    case editPickems
    case viewPickems
    case watchLive
    case seeResults

    var title: String {
        switch self {
        case .makeSelections: return "Make Selections"
        case .editSelections: return "Edit Selections"
        case .waitingOnSelections: return "Waiting on Selections"
        case .makePickems: return "Make Pickems"
        case .finishPickems: return "Finish Pickems"
        case .submitPickems: return "Submit Pickems"
        case .editPickems: return "Edit Pickems"
        case .viewPickems: return "View Pickems"
        case .watchLive: return "Watch Live"
        case .seeResults: return "See Results"
        }
    }

    /// Nil when the button should not switch tabs (wait state).
    var destinationTab: AppTab? {
        switch self {
        case .waitingOnSelections:
            return nil
        case .makeSelections, .editSelections:
            return .selections
        case .makePickems, .finishPickems, .submitPickems, .editPickems, .viewPickems, .watchLive, .seeResults:
            return .pickems
        }
    }
}

enum HomeCTAResolver {
    static func resolve(
        week: WeekSummary?,
        isCommissioner: Bool,
        didSubmitNominations: Bool,
        userNominationCount: Int,
        pickCount: Int,
        slateCount: Int,
        pickemsLocked: Bool,
        picksSubmitted: Bool
    ) -> HomeCTA {
        guard let week else { return .makeSelections }
        switch week.status {
        case .selection:
            if week.selectionMode == .commissioner, !isCommissioner {
                return .waitingOnSelections
            }
            let perMember = max(week.selectionsPerMember, 1)
            if didSubmitNominations || userNominationCount >= perMember {
                return .editSelections
            }
            return .makeSelections
        case .picking:
            if pickemsLocked { return .viewPickems }
            if picksSubmitted { return .editPickems }
            if pickCount == 0 { return .makePickems }
            if slateCount > 0, pickCount < slateCount { return .finishPickems }
            return .submitPickems
        case .locked:
            return .watchLive
        case .scored:
            return .seeResults
        }
    }
}

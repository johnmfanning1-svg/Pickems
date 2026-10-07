import Foundation

/// Commissioner "League type" picker in Commissioner Settings → Scoring. The
/// write is the `setLeaguePickMode` callable (`firebase/functions/src/leaguePickMode.ts`);
/// this decides whether the change can include the current week, whether to ask,
/// and holds the copy.
enum LeaguePickModeSwitch {
    /// Where the league's current week is.
    enum Phase: Equatable {
        /// No current week loaded.
        case noCurrentWeek
        /// Week is in Selections and nobody has selected a game yet (or it has a fixed slate).
        case selectionsNotStarted(weekId: String)
        /// Selections have started; Pickems have not opened.
        case selectionsStarted(weekId: String)
        /// Pickems opened (picking or locked) for this week.
        case pickemsStarted(weekId: String)
        /// This week is already scored.
        case weekScored(weekId: String)
    }

    enum Decision: Equatable {
        /// Apply to this week (if any) and every week after. No prompt.
        case applyNow(weekId: String?)
        /// Ask: this week and going forward, or start next week.
        case ask(weekId: String)
        /// Only next week on. Confirm once; never offer this week.
        case nextWeekOnly(weekId: String)
    }

    static func phase(week: WeekSummary?, selectionsMade: Int) -> Phase {
        guard let week else { return .noCurrentWeek }
        switch week.status {
        case .selection:
            if week.skipsSelection { return .selectionsNotStarted(weekId: week.id) }
            let started: Bool = selectionsMade > 0 || week.nominationCount > 0
            return started ? .selectionsStarted(weekId: week.id) : .selectionsNotStarted(weekId: week.id)
        case .picking, .locked:
            return .pickemsStarted(weekId: week.id)
        case .scored:
            return .weekScored(weekId: week.id)
        }
    }

    static func decision(for phase: Phase) -> Decision {
        switch phase {
        case .noCurrentWeek:
            return .applyNow(weekId: nil)
        case .selectionsNotStarted(let weekId):
            return .applyNow(weekId: weekId)
        case .selectionsStarted(let weekId):
            return .ask(weekId: weekId)
        case .pickemsStarted(let weekId), .weekScored(let weekId):
            return .nextWeekOnly(weekId: weekId)
        }
    }

    // MARK: - Copy

    static let applyNowTitle = "Apply to this week and going forward"
    static let nextWeekTitle = "Start next week"

    /// Case b: Selections started, Pickems not open.
    static func askTitle(newMode: PickMode) -> String {
        "Switch to \(newMode.displayName)?"
    }

    static func askMessage(newMode: PickMode, currentMode: PickMode) -> String {
        let applyLine = "“\(applyNowTitle)” scores this week \(newMode.displayName) too. Selections already made stay."
        let nextLine = "“\(nextWeekTitle)” keeps this week \(currentMode.displayName)."
        return "Selections have already started this week.\n\n" + applyLine + "\n\n" + nextLine
    }

    /// Case c: Pickems opened (or the week is scored). Only next week is offered.
    static func nextWeekOnlyTitle(newMode: PickMode) -> String {
        "Switch to \(newMode.displayName) next week?"
    }

    static func nextWeekOnlyMessage(newMode: PickMode, currentMode: PickMode, weekScored: Bool) -> String {
        let reason = weekScored
            ? "This week is already scored"
            : "Pickems are already open for this week"
        return "\(reason), so it stays \(currentMode.displayName). \(newMode.displayName) starts next week."
    }

    static func successMessage(newMode: PickMode, appliedToCurrentWeek: Bool, hadCurrentWeek: Bool, currentMode: PickMode) -> String {
        if !hadCurrentWeek {
            return "League type is \(newMode.displayName) for every week going forward."
        }
        if appliedToCurrentWeek {
            return "League type is \(newMode.displayName), starting this week."
        }
        return "League type is \(newMode.displayName) starting next week. This week stays \(currentMode.displayName)."
    }

    static let footer = "ATS grades the cover. Straight Up grades the outright winner (a tie is a push). Before Selections start, a change applies to this week. Once Selections start, you choose this week or next week. Once Pickems open, it starts next week."
}

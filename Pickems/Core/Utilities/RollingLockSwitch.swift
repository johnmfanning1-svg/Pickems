import Foundation

/// Commissioner "Switch to rolling lock". The write itself is the
/// `setRollingLock` callable (`firebase/functions/src/rollingLock.ts`); this
/// decides whether to ask "Apply to current week?" and holds the copy.
enum RollingLockSwitch {
    enum CurrentWeekPhase: Equatable {
        /// No week in progress: change the league setting, no prompt.
        case notInProgress
        /// Week is picking/locked, has started (or is locked), isn't scored,
        /// and still has games to kick off: ask whether to apply it now.
        case inProgress(weekId: String)
        /// Week is in progress but every game has kicked off. Rolling lock can
        /// only start next week, so there is nothing to ask.
        case allGamesStarted
    }

    /// Same definition as `weekInProgress` in rollingLock.ts.
    static func currentWeekPhase(_ week: WeekSummary?, now: Date = Date()) -> CurrentWeekPhase {
        guard let week else { return .notInProgress }
        guard week.status == .picking || week.status == .locked else { return .notInProgress }
        // A week that already opened on rolling lock has nothing to switch.
        guard !week.isRollingLock else { return .notInProgress }

        let kickoffMap: [String: Date] = week.gameKickoffs ?? [:]
        let kickoffs: [Date] = Array(kickoffMap.values)
        let firstKickoffPassed: Bool
        if let first = kickoffs.min() {
            firstKickoffPassed = first <= now
        } else {
            firstKickoffPassed = false
        }
        let started: Bool = week.status == .locked || firstKickoffPassed
        guard started else { return .notInProgress }

        guard let last = kickoffs.max(), last > now else { return .allGamesStarted }
        return .inProgress(weekId: week.id)
    }

    /// The league's in-progress week across every loaded week (the commissioner
    /// may be browsing a different week). Prefers a week that can still switch.
    static func leaguePhase(weeks: [WeekSummary], now: Date = Date()) -> (phase: CurrentWeekPhase, week: WeekSummary?) {
        var seen = Set<String>()
        var allStartedWeek: WeekSummary?
        for week in weeks where seen.insert(week.id).inserted {
            switch currentWeekPhase(week, now: now) {
            case .inProgress:
                return (.inProgress(weekId: week.id), week)
            case .allGamesStarted:
                if allStartedWeek == nil { allStartedWeek = week }
            case .notInProgress:
                continue
            }
        }
        if let allStartedWeek { return (.allGamesStarted, allStartedWeek) }
        return (.notInProgress, nil)
    }

    static let buttonTitle = "Switch to Rolling Lock"
    static let promptTitle = "Apply to current week?"
    static let applyNowTitle = "Yes"
    static let nextWeekTitle = "No"

    /// The four plain-language warnings shown before applying mid-week.
    static let disclaimerPoints: [String] = [
        "Picks may already have been visible to the league since this week locked.",
        "Members who already submitted can change picks on games that haven't started.",
        "Games that have started stay locked.",
        "Any game a member misses counts as a loss.",
    ]

    static var promptMessage: String {
        let intro = "Yes switches this week to rolling lock now. No keeps this week as it is and starts rolling lock next week."
        let bullets: [String] = disclaimerPoints.map { (point: String) -> String in "• \(point)" }
        let bulletList: String = bullets.joined(separator: "\n")
        return intro + "\n\n" + bulletList
    }

    static func successMessage(appliedToWeek: Bool, weekNumber: Int?, askedToApply: Bool = false) -> String {
        if askedToApply && !appliedToWeek {
            return "Rolling lock is on. This week was already on rolling lock."
        }
        if appliedToWeek {
            let label: String
            if let weekNumber {
                label = "Week \(weekNumber)"
            } else {
                label = "This week"
            }
            return "Rolling lock is on. \(label) now locks each game at its own kickoff."
        }
        return "Rolling lock is on. It starts when next week opens."
    }

    static let allGamesStartedNote =
        "Every game this week has already kicked off, so rolling lock starts next week."
}

import Foundation

enum SeasonLedgerWeekEligibility {
    static func eligibleWeeks(
        from fetched: [WeekSummary],
        seasonYear: Int,
        now: Date = Date()
    ) -> [WeekSummary] {
        fetched
            .filter { week in
                guard week.seasonYear == seasonYear else { return false }
                return isEligible(week, now: now)
            }
            .sorted {
                if $0.seasonYear != $1.seasonYear { return $0.seasonYear < $1.seasonYear }
                return $0.weekNumber < $1.weekNumber
            }
    }

    static func isEligible(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .scored, .locked:
            return true
        case .picking, .selection:
            return WeekTransition.pickemsShouldShowLeagueBoard(week, now: now)
        }
    }
}
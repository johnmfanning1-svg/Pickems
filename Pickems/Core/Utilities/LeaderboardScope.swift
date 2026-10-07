import Foundation

/// This Week / Season segment on the Leagues leaderboard.
enum LeaderboardScope {
    enum Scope: Hashable {
        case thisWeek
        case season

        var showsWeeklyRecord: Bool {
            switch self {
            case .thisWeek:
                return true
            case .season:
                return false
            }
        }
    }

    /// A picker move the member made for one league. Cleared when they switch leagues.
    struct ManualChoice: Equatable {
        var leagueId: String? = nil
        var scope: Scope? = nil

        /// Keep the choice across a missing league id. Firestore can publish `nil`
        /// for a frame without the member leaving the league. A real chip switch
        /// (one id to a different id) drops the choice so the new league gets the default.
        static func afterLeagueChange(
            from previousLeagueId: String?,
            to nextLeagueId: String?,
            current: ManualChoice
        ) -> ManualChoice {
            guard let previousLeagueId, let nextLeagueId else { return current }
            guard previousLeagueId != nextLeagueId else { return current }
            return ManualChoice()
        }
    }

    /// Season unless the current week is in progress.
    ///
    /// In progress means Pickems are open (`.picking`) or locked and the week is
    /// not scored yet — the same gate as `WeekTransition.arePickemsOpen`, minus
    /// `.scored`. Selections, skipped/upcoming weeks (they stay in `.selection`),
    /// a completed week, and a missing week all default to Season.
    static func defaultScope(for week: WeekSummary?) -> Scope {
        guard let week else { return .season }
        switch week.status {
        case .picking, .locked:
            guard WeekTransition.arePickemsOpen(week) else { return .season }
            return .thisWeek
        case .selection, .scored:
            return .season
        }
    }

    /// The segment to show. A manual choice wins only while the member is still
    /// on the league they chose it for.
    static func resolvedScope(
        week: WeekSummary?,
        leagueId: String?,
        manual: ManualChoice
    ) -> Scope {
        if let leagueId, manual.leagueId == leagueId, let chosen = manual.scope {
            return chosen
        }
        return defaultScope(for: week)
    }
}

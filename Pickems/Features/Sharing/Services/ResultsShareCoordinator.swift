import Foundation

/// Call when weekly or season results are finalized to surface share prompts.
@MainActor
final class ResultsShareCoordinator: ObservableObject {
    @Published var pendingWeeklyShare: WeeklyResult?
    @Published var pendingSeasonShare: SeasonStanding?

    func presentWeeklyShareIfEligible(_ result: WeeklyResult) {
        pendingWeeklyShare = result
    }

    func presentSeasonShareIfEligible(_ standing: SeasonStanding) {
        pendingSeasonShare = standing
    }

    func clearWeekly() {
        pendingWeeklyShare = nil
    }

    func clearSeason() {
        pendingSeasonShare = nil
    }
}

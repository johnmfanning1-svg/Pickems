import Foundation

/// Which week sections start expanded in Season Ledger Detailed view.
enum SeasonLedgerWeekExpansion {
    /// Detailed view opens with every week collapsed.
    static func initialExpandedWeekIds(data _: SeasonLedgerSeasonData) -> Set<String> {
        []
    }
}
import Foundation

/// Sort order for week chips and commissioner lists (`2026-W*` then `2026-BOWL*`).
enum PickemsWeekSort {
    static func rank(seasonYear: Int, weekId: String, weekNumber: Int) -> (seasonYear: Int, ordinal: Int) {
        if weekId.range(of: #"^\d{4}-BOWL"#, options: .regularExpression) != nil {
            let bowlOrdinal: Int
            if weekId.hasSuffix("BOWL2") {
                bowlOrdinal = 902
            } else if weekId.hasSuffix("BOWL1") || weekId.hasSuffix("BOWL") {
                bowlOrdinal = 901
            } else {
                bowlOrdinal = 950
            }
            return (seasonYear, bowlOrdinal)
        }
        return (seasonYear, weekNumber)
    }
}
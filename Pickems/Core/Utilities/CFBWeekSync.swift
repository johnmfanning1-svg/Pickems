import Foundation

enum CFBWeekSync {
    static func weekId(for info: CFBWeekInfo) -> String {
        "\(info.seasonYear)-W\(info.weekNumber)"
    }

    static func fallbackWeekId() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let week = estimatedCFBWeek()
        return "\(year)-W\(week)"
    }

    static func estimatedCFBWeek() -> Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let augustFirst = calendar.date(from: DateComponents(year: year, month: 8, day: 25)) ?? Date()
        let weeks = calendar.dateComponents([.weekOfYear], from: augustFirst, to: Date()).weekOfYear ?? 0
        return max(1, min(15, weeks + 1))
    }

    static func makeWeekSummary(id: String, info: CFBWeekInfo, rules: GroupRules) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: info.seasonYear,
            weekNumber: info.weekNumber,
            status: .selection,
            slateSize: rules.slateSize,
            selectionMode: rules.selectionMode,
            selectionsPerMember: rules.selectionsPerMember,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0
        )
    }
}

import Foundation

/// Bowl week copy for the widget extension (keep in sync with `CFBBowlSeason.userFacingBowlWeekName`).
enum WidgetWeekLabel {
    static let bowlBonanza = "Bowl Bonanza"

    static func display(weekId: String?, weekNumber: Int, weekLabel: String? = nil) -> String {
        if let weekLabel, !weekLabel.isEmpty { return weekLabel }
        if let weekId, isBowlWeekId(weekId) { return bowlBonanza }
        return "Week \(weekNumber)"
    }

    static func shortEyebrow(weekId: String?, weekNumber: Int, weekLabel: String? = nil) -> String {
        if let weekLabel, !weekLabel.isEmpty, weekLabel != "Week \(weekNumber)" {
            return weekLabel
        }
        if let weekId, isBowlWeekId(weekId) { return bowlBonanza }
        return "Wk \(weekNumber)"
    }

    static func liveActivityWeekLine(
        weekId: String,
        weekNumber: Int,
        weekLabel: String = ""
    ) -> String {
        let trimmed = weekLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if isBowlWeekId(weekId) { return bowlBonanza }
        return "W\(weekNumber)"
    }

    private static func isBowlWeekId(_ id: String) -> Bool {
        id.range(of: #"^\d{4}-BOWL\d*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension StandingsSnapshot {
    var userFacingWeekTitle: String {
        WidgetWeekLabel.display(weekId: weekId, weekNumber: weekNumber, weekLabel: weekLabel)
    }

    var shortWeekEyebrow: String {
        WidgetWeekLabel.shortEyebrow(weekId: weekId, weekNumber: weekNumber, weekLabel: weekLabel)
    }

    var deepLinkWeekId: String {
        if let weekId, !weekId.isEmpty { return weekId }
        return "\(seasonYear)-W\(weekNumber)"
    }
}
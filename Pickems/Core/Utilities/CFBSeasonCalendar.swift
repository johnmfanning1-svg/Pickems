import Foundation

/// College football calendar anchors for widgets and in-app season gates.
enum CFBSeasonCalendar {
    /// First day of season kickoff for a season year (US Eastern, start of day).
    static func seasonKickoff(forSeasonYear year: Int) -> Date {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        // Published kickoff openers when known; otherwise last Thursday of August.
        let components: DateComponents
        switch year {
        case 2026:
            components = DateComponents(year: 2026, month: 8, day: 27, hour: 0, minute: 0)
        case 2025:
            components = DateComponents(year: 2025, month: 8, day: 23, hour: 0, minute: 0)
        default:
            components = DateComponents(year: year, month: 8, day: lastThursdayDayOfAugust(year), hour: 0, minute: 0)
        }
        return eastern.date(from: components) ?? Date()
    }

    /// `true` before that season year's kickoff day (offseason / preseason countdown window).
    static func isPreseason(on date: Date = Date()) -> Bool {
        let year = seasonYear(containing: date)
        return date < seasonKickoff(forSeasonYear: year)
    }

    /// Season year whose kickoff we are counting down to, or currently playing.
    static func seasonYear(containing date: Date = Date()) -> Int {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return eastern.component(.year, from: date)
    }

    static func nextSeasonKickoff(on date: Date = Date()) -> Date {
        let year = seasonYear(containing: date)
        let thisYear = seasonKickoff(forSeasonYear: year)
        if date < thisYear { return thisYear }
        return seasonKickoff(forSeasonYear: year + 1)
    }

    /// Days / hours / minutes remaining (floored). Never negative.
    static func countdown(to target: Date, from date: Date = Date()) -> (days: Int, hours: Int, minutes: Int) {
        let remaining = max(0, target.timeIntervalSince(date))
        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        return (days, hours, minutes)
    }

    static func countdownSummary(to target: Date, from date: Date = Date()) -> String {
        let c = countdown(to: target, from: date)
        if c.days > 0 {
            return "\(c.days)d \(c.hours)h"
        }
        if c.hours > 0 {
            return "\(c.hours)h \(c.minutes)m"
        }
        return "\(c.minutes)m"
    }

    private static func lastThursdayDayOfAugust(_ year: Int) -> Int {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        guard let august = eastern.date(from: DateComponents(year: year, month: 8, day: 1)),
              let range = eastern.range(of: .day, in: .month, for: august) else {
            return 28
        }
        for day in stride(from: range.upperBound - 1, through: 1, by: -1) {
            guard let date = eastern.date(from: DateComponents(year: year, month: 8, day: day)) else { continue }
            if eastern.component(.weekday, from: date) == 5 { // Thursday
                return day
            }
        }
        return 28
    }
}

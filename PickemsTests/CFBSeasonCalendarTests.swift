import Foundation
import Testing
@testable import Pickems

struct CFBSeasonCalendarTests {
    private var eastern: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        eastern.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func seasonYearStays2026ThroughJanuary2027() {
        #expect(CFBSeasonCalendar.seasonYear(containing: date(2027, 1, 15)) == 2026)
        #expect(CFBSeasonCalendar.seasonYear(containing: date(2027, 2, 1)) == 2027)
    }
}
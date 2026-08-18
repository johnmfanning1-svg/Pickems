import Foundation
import Testing
@testable import Pickems

struct CFBWeekCalendarTests {
    private var eastern: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        eastern.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func espnScoreboardWeekMapsZeroToOne() {
        #expect(CFBWeekCalendar.espnScoreboardWeek(0) == 1)
        #expect(CFBWeekCalendar.espnScoreboardWeek(1) == 1)
        #expect(CFBWeekCalendar.espnScoreboardWeek(2) == 2)
    }

    @Test func resolveUsesWeekZeroBeforeAugust30() {
        let info = CFBWeekInfo(seasonYear: 2026, weekNumber: 1, seasonType: 2, label: "")
        let app = CFBWeekCalendar.resolve(espn: info, now: date(2026, 8, 28))
        #expect(app.weekNumber == 0)
        #expect(app.id == "2026-W0")
        #expect(app.espnWeekNumber == 1)
    }

    @Test func resolveUsesWeekOneOnAugust30() {
        let info = CFBWeekInfo(seasonYear: 2026, weekNumber: 1, seasonType: 2, label: "")
        let app = CFBWeekCalendar.resolve(espn: info, now: date(2026, 8, 30, hour: 0))
        #expect(app.weekNumber == 1)
        #expect(app.id == "2026-W1")
    }

    @Test func resolvePassesThroughEspnWeek2() {
        let info = CFBWeekInfo(seasonYear: 2026, weekNumber: 2, seasonType: 2, label: "")
        let app = CFBWeekCalendar.resolve(espn: info, now: date(2026, 9, 8))
        #expect(app.weekNumber == 2)
        #expect(app.id == "2026-W2")
    }

    @Test func resolvePassesThrough2027() {
        let info = CFBWeekInfo(seasonYear: 2027, weekNumber: 1, seasonType: 2, label: "")
        let app = CFBWeekCalendar.resolve(espn: info, now: date(2027, 8, 28))
        #expect(app.weekNumber == 1)
        #expect(app.id == "2027-W1")
    }

    @Test func weekZeroDateFilterKeepsAugust29Only() {
        let aug29 = date(2026, 8, 29, hour: 12)
        let sep5 = date(2026, 9, 5, hour: 12)
        #expect(CFBWeekCalendar.includesGame(kickoff: aug29, seasonYear: 2026, appWeekNumber: 0))
        #expect(!CFBWeekCalendar.includesGame(kickoff: sep5, seasonYear: 2026, appWeekNumber: 0))
        #expect(!CFBWeekCalendar.includesGame(kickoff: aug29, seasonYear: 2026, appWeekNumber: 1))
        #expect(CFBWeekCalendar.includesGame(kickoff: sep5, seasonYear: 2026, appWeekNumber: 1))
        #expect(CFBWeekCalendar.includesGame(kickoff: aug29, seasonYear: 2026, appWeekNumber: 2))
    }

    @Test func weekIdResolvesEspnWeek1ToWeekZero() {
        let info = CFBWeekInfo(seasonYear: 2026, weekNumber: 1, seasonType: 2, label: "")
        #expect(CFBWeekSync.weekId(for: info, now: date(2026, 8, 18)) == "2026-W0")
    }

    @Test func appSeasonWeeksSplitsEspnWeek1In2026() {
        let espn = [
            ESPNCalendarWeek(espnWeekNumber: 1, detail: "Aug 22-Sep 7"),
            ESPNCalendarWeek(espnWeekNumber: 2, detail: "Sep 8-13"),
        ]
        let weeks = CFBWeekCalendar.appSeasonWeeks(seasonYear: 2026, espnWeeks: espn)
        #expect(weeks.map(\.id) == ["2026-W0", "2026-W1", "2026-W2"])
        #expect(weeks[0].dateRangeLabel == "Aug 29")
        #expect(weeks[1].dateRangeLabel == "Sep 3-7")
        #expect(weeks[2].dateRangeLabel == "Sep 8-13")
        #expect(weeks[0].espnWeekNumber == 1)
        #expect(weeks[1].espnWeekNumber == 1)
        #expect(weeks[2].espnWeekNumber == 2)
    }

    @Test func appSeasonWeeksDoesNotSplit2027() {
        let espn = [ESPNCalendarWeek(espnWeekNumber: 1, detail: "Aug 28-Sep 7")]
        let weeks = CFBWeekCalendar.appSeasonWeeks(seasonYear: 2027, espnWeeks: espn)
        #expect(weeks.map(\.id) == ["2027-W1"])
        #expect(weeks[0].dateRangeLabel == "Aug 28-Sep 7")
    }

    @Test func fallbackSeasonWeeksCoversFull2026RegularSeason() {
        let weeks = CFBWeekCalendar.fallbackSeasonWeeks(seasonYear: 2026)
        #expect(weeks.first?.id == "2026-W0")
        #expect(weeks.last?.id == "2026-W15")
        #expect(weeks.count == 16)
    }
}

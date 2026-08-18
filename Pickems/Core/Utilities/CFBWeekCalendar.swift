import Foundation

/// Resolved Pickems week after applying year-keyed overlays on top of ESPN.
struct CFBAppWeek: Equatable {
    let seasonYear: Int
    let weekNumber: Int
    let espnWeekNumber: Int
    let seasonType: Int

    var id: String { "\(seasonYear)-W\(weekNumber)" }

    var label: String { "Season \(seasonYear) | Week \(weekNumber)" }
}

/// One slot in the Selections week strip (ESPN regular season, plus the 2026 Week 0 split).
struct CFBSeasonWeek: Equatable, Identifiable {
    let seasonYear: Int
    let weekNumber: Int
    let espnWeekNumber: Int
    let dateRangeLabel: String

    var id: String { "\(seasonYear)-W\(weekNumber)" }
}

/// ESPN regular-season calendar row (`leagues[].calendar[].entries[]`).
struct ESPNCalendarWeek: Equatable {
    let espnWeekNumber: Int
    let detail: String
}

/// 2026-only split: ESPN's mega Week 1 is two Pickems weeks.
/// Week 0 = Saturday Aug 29 ET openers; Week 1 = the rest (Sep 3–7).
enum CFBWeekCalendar {
    static let weekZeroSlateSource = "fixedBoard"

    /// Midnight ET on Sunday Aug 30, 2026 — after this, current week is 2026-W1.
    static func weekZeroWindowEnd() -> Date {
        easternDate(year: 2026, month: 8, day: 30) ?? Date.distantPast
    }

    static func espnScoreboardWeek(_ appWeekNumber: Int) -> Int {
        appWeekNumber == 0 ? 1 : appWeekNumber
    }

    static func resolve(espn: CFBWeekInfo, now: Date = Date()) -> CFBAppWeek {
        let weekNumber = resolveAppWeekNumber(
            seasonYear: espn.seasonYear,
            espnWeekNumber: espn.weekNumber,
            now: now
        )
        return CFBAppWeek(
            seasonYear: espn.seasonYear,
            weekNumber: weekNumber,
            espnWeekNumber: espn.weekNumber,
            seasonType: espn.seasonType
        )
    }

    static func resolveAppWeekNumber(seasonYear: Int, espnWeekNumber: Int, now: Date = Date()) -> Int {
        guard seasonYear == 2026, espnWeekNumber == 1 else { return espnWeekNumber }
        return now < weekZeroWindowEnd() ? 0 : 1
    }

    static func isWeekZeroKickoff(_ date: Date) -> Bool {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let parts = eastern.dateComponents([.year, .month, .day], from: date)
        return parts.year == 2026 && parts.month == 8 && parts.day == 29
    }

    /// Whether a game belongs on the given Pickems week. Unsplitting years include every game.
    static func includesGame(kickoff: Date, seasonYear: Int, appWeekNumber: Int) -> Bool {
        guard seasonYear == 2026, appWeekNumber == 0 || appWeekNumber == 1 else { return true }
        let isZero = isWeekZeroKickoff(kickoff)
        return appWeekNumber == 0 ? isZero : !isZero
    }

    static func isFixedSlate(weekNumber: Int, slateSource: String?) -> Bool {
        weekNumber == 0 || slateSource == weekZeroSlateSource
    }

    /// Maps ESPN regular-season weeks onto Pickems weeks. 2026 splits ESPN Week 1 into W0 + W1.
    static func appSeasonWeeks(
        seasonYear: Int,
        espnWeeks: [ESPNCalendarWeek]
    ) -> [CFBSeasonWeek] {
        var result: [CFBSeasonWeek] = []
        for entry in espnWeeks.sorted(by: { $0.espnWeekNumber < $1.espnWeekNumber }) {
            if seasonYear == 2026, entry.espnWeekNumber == 1 {
                result.append(
                    CFBSeasonWeek(
                        seasonYear: seasonYear,
                        weekNumber: 0,
                        espnWeekNumber: 1,
                        dateRangeLabel: "Aug 29"
                    )
                )
                result.append(
                    CFBSeasonWeek(
                        seasonYear: seasonYear,
                        weekNumber: 1,
                        espnWeekNumber: 1,
                        dateRangeLabel: "Sep 3-7"
                    )
                )
                continue
            }
            result.append(
                CFBSeasonWeek(
                    seasonYear: seasonYear,
                    weekNumber: entry.espnWeekNumber,
                    espnWeekNumber: entry.espnWeekNumber,
                    dateRangeLabel: entry.detail
                )
            )
        }
        return result
    }

    /// Offline / decode-miss fallback: 2026 ESPN windows, otherwise Week 1...15.
    static func fallbackSeasonWeeks(seasonYear: Int) -> [CFBSeasonWeek] {
        if seasonYear == 2026 {
            return appSeasonWeeks(seasonYear: 2026, espnWeeks: espn2026RegularSeason)
        }
        return (1...15).map {
            CFBSeasonWeek(
                seasonYear: seasonYear,
                weekNumber: $0,
                espnWeekNumber: $0,
                dateRangeLabel: "Week \($0)"
            )
        }
    }

    private static let espn2026RegularSeason: [ESPNCalendarWeek] = [
        ESPNCalendarWeek(espnWeekNumber: 1, detail: "Aug 22-Sep 7"),
        ESPNCalendarWeek(espnWeekNumber: 2, detail: "Sep 8-13"),
        ESPNCalendarWeek(espnWeekNumber: 3, detail: "Sep 14-20"),
        ESPNCalendarWeek(espnWeekNumber: 4, detail: "Sep 21-27"),
        ESPNCalendarWeek(espnWeekNumber: 5, detail: "Sep 28-Oct 4"),
        ESPNCalendarWeek(espnWeekNumber: 6, detail: "Oct 5-11"),
        ESPNCalendarWeek(espnWeekNumber: 7, detail: "Oct 12-18"),
        ESPNCalendarWeek(espnWeekNumber: 8, detail: "Oct 19-25"),
        ESPNCalendarWeek(espnWeekNumber: 9, detail: "Oct 26-Nov 1"),
        ESPNCalendarWeek(espnWeekNumber: 10, detail: "Nov 2-8"),
        ESPNCalendarWeek(espnWeekNumber: 11, detail: "Nov 9-15"),
        ESPNCalendarWeek(espnWeekNumber: 12, detail: "Nov 16-22"),
        ESPNCalendarWeek(espnWeekNumber: 13, detail: "Nov 23-29"),
        ESPNCalendarWeek(espnWeekNumber: 14, detail: "Nov 30-Dec 6"),
        ESPNCalendarWeek(espnWeekNumber: 15, detail: "Dec 7-12"),
    ]

    private static func easternDate(year: Int, month: Int, day: Int) -> Date? {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return eastern.date(from: DateComponents(year: year, month: month, day: day, hour: 0, minute: 0))
    }
}

extension Array where Element == ESPNGame {
    func matching(seasonYear: Int, appWeekNumber: Int) -> [ESPNGame] {
        filter { CFBWeekCalendar.includesGame(kickoff: $0.kickoff, seasonYear: seasonYear, appWeekNumber: appWeekNumber) }
    }
}

extension Array where Element == ESPNLiveGameCard {
    func matching(seasonYear: Int, appWeekNumber: Int) -> [ESPNLiveGameCard] {
        filter { CFBWeekCalendar.includesGame(kickoff: $0.kickoff, seasonYear: seasonYear, appWeekNumber: appWeekNumber) }
    }
}

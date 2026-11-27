import Foundation

/// Commissioner default for `weeks/{id}.selectionDeadline` (member Selections).
struct DefaultSelectionLock: Codable, Equatable {
    var enabled: Bool
    /// ISO-8601 weekday: 1 = Monday … 7 = Sunday.
    var weekday: Int
    var hour: Int
    var minute: Int
    /// IANA identifier, e.g. `America/New_York`.
    var timeZone: String

    static let disabled = DefaultSelectionLock(
        enabled: false,
        weekday: 3,
        hour: 23,
        minute: 59,
        timeZone: TimeZone.current.identifier
    )

    func configuredTimeZone() -> TimeZone {
        TimeZone(identifier: timeZone) ?? .current
    }

    /// Late-week warning: Fri/Sat/Sun, or Thu at 7:00 PM or later in the lock zone.
    func showsLateWeekWarning() -> Bool {
        guard enabled else { return false }
        if weekday >= 5 { return true }
        if weekday == 4, hour > 19 || (hour == 19 && minute > 0) { return true }
        return false
    }
}

enum DefaultSelectionLockMath {
    /// Absolute instant for this lock inside the CFB week window. Past instants are still returned.
    static func deadline(
        for lock: DefaultSelectionLock,
        seasonYear: Int,
        weekNumber: Int,
        weekDocId: String? = nil
    ) -> Date? {
        guard lock.enabled else { return nil }
        let window: (start: Date, end: Date)?
        if let weekDocId {
            window = CFBWeekCalendar.weekWindow(weekDocId: weekDocId, seasonYear: seasonYear, weekNumber: weekNumber)
        } else {
            window = CFBWeekCalendar.weekWindow(seasonYear: seasonYear, weekNumber: weekNumber)
        }
        guard let window else { return nil }
        guard let zone = TimeZone(identifier: lock.timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        var day = calendar.startOfDay(for: window.start)
        let endDay = calendar.startOfDay(for: window.end)
        while day <= endDay {
            if isoWeekday(from: calendar.component(.weekday, from: day)) == lock.weekday {
                var parts = calendar.dateComponents([.year, .month, .day], from: day)
                parts.hour = lock.hour
                parts.minute = lock.minute
                parts.second = 0
                parts.timeZone = zone
                return calendar.date(from: parts)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nil
    }

    static func isoWeekday(from calendarWeekday: Int) -> Int {
        // Calendar: Sun=1 … Sat=7 → ISO: Mon=1 … Sun=7
        calendarWeekday == 1 ? 7 : calendarWeekday - 1
    }

    /// Stamping path: nil when the computed instant is not strictly after `now`.
    static func futureDeadline(
        for lock: DefaultSelectionLock,
        seasonYear: Int,
        weekNumber: Int,
        now: Date = Date(),
        weekDocId: String? = nil
    ) -> Date? {
        guard let raw = deadline(for: lock, seasonYear: seasonYear, weekNumber: weekNumber, weekDocId: weekDocId) else {
            return nil
        }
        return raw > now ? raw : nil
    }

    static func isoWeekdayLabel(_ iso: Int) -> String {
        switch iso {
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        case 7: return "Sunday"
        default: return "Day \(iso)"
        }
    }
}

/// ESPN-style week date labels → absolute Eastern bounds (inclusive days).
enum CFBWeekDateWindow {
    static func parse(label: String, seasonYear: Int) -> (start: Date, end: Date)? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Week ") {
            return syntheticWindow(seasonYear: seasonYear, weekNumber: trimmed)
        }
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current

        if trimmed.contains("-") {
            let chunks = trimmed.split(separator: "-", maxSplits: 1).map(String.init)
            guard chunks.count == 2,
                  let start = parseDayToken(chunks[0], defaultYear: seasonYear, eastern: eastern) else {
                return nil
            }
            let end: Date
            if chunks[1].contains(" ") {
                guard let parsedEnd = parseDayToken(
                    chunks[1],
                    defaultYear: seasonYear,
                    eastern: eastern,
                    anchor: start
                ) else { return nil }
                end = parsedEnd
            } else if let endDay = Int(chunks[1].trimmingCharacters(in: .whitespaces)) {
                var parts = eastern.dateComponents([.year, .month], from: start)
                parts.day = endDay
                guard let parsedEnd = eastern.date(from: parts) else { return nil }
                end = parsedEnd
            } else {
                return nil
            }
            return (startOfDay(start, eastern: eastern), endOfDay(end, eastern: eastern))
        }
        guard let day = parseDayToken(trimmed, defaultYear: seasonYear, eastern: eastern) else { return nil }
        return (startOfDay(day, eastern: eastern), endOfDay(day, eastern: eastern))
    }

    private static func syntheticWindow(seasonYear: Int, weekNumber: String) -> (start: Date, end: Date)? {
        guard let number = Int(weekNumber.replacingOccurrences(of: "Week ", with: "")) else { return nil }
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let kickoff = CFBSeasonCalendar.seasonKickoff(forSeasonYear: seasonYear)
        guard let start = eastern.date(byAdding: .day, value: max(0, number - 1) * 7, to: kickoff),
              let end = eastern.date(byAdding: .day, value: 6, to: start) else {
            return nil
        }
        return (startOfDay(start, eastern: eastern), endOfDay(end, eastern: eastern))
    }

    private static func parseDayToken(
        _ token: String,
        defaultYear: Int,
        eastern: Calendar,
        anchor: Date? = nil
    ) -> Date? {
        let parts = token.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count == 2, let month = monthNumber(String(parts[0])) else { return nil }
        guard let day = Int(parts[1]) else { return nil }
        var year = defaultYear
        if let anchor {
            let anchorMonth = eastern.component(.month, from: anchor)
            if month < anchorMonth { year += 1 }
        }
        return eastern.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func monthNumber(_ abbrev: String) -> Int? {
        switch abbrev.lowercased() {
        case "jan": return 1
        case "feb": return 2
        case "mar": return 3
        case "apr": return 4
        case "may": return 5
        case "jun": return 6
        case "jul": return 7
        case "aug": return 8
        case "sep": return 9
        case "oct": return 10
        case "nov": return 11
        case "dec": return 12
        default: return nil
        }
    }

    private static func startOfDay(_ date: Date, eastern: Calendar) -> Date {
        eastern.startOfDay(for: date)
    }

    private static func endOfDay(_ date: Date, eastern: Calendar) -> Date {
        var parts = eastern.dateComponents([.year, .month, .day], from: date)
        parts.hour = 23
        parts.minute = 59
        parts.second = 59
        return eastern.date(from: parts) ?? date
    }
}

extension CFBWeekCalendar {
    /// Inclusive ESPN-shaped window for a Pickems week (`fallbackSeasonWeeks` labels).
    static func weekWindow(seasonYear: Int, weekNumber: Int) -> (start: Date, end: Date)? {
        let weeks = fallbackSeasonWeeks(seasonYear: seasonYear)
        guard let slot = weeks.first(where: { $0.weekNumber == weekNumber && $0.pickemsWeekId == nil }) else {
            return nil
        }
        return CFBWeekDateWindow.parse(label: slot.dateRangeLabel, seasonYear: seasonYear)
    }

    static func weekWindow(weekDocId: String, seasonYear: Int, weekNumber: Int) -> (start: Date, end: Date)? {
        if let slot = bowlCalendarSlots(seasonYear: seasonYear).first(where: { $0.id == weekDocId }) {
            return CFBWeekDateWindow.parse(label: slot.dateRangeLabel, seasonYear: seasonYear)
        }
        return weekWindow(seasonYear: seasonYear, weekNumber: weekNumber)
    }
}

enum DefaultSelectionLockRulesSave {
    /// Minted selection weeks that should receive the league default after rules save.
    static func weeksToStamp(
        among weeks: [WeekSummary],
        lock: DefaultSelectionLock,
        rules: GroupRules,
        now: Date = Date()
    ) -> [(week: WeekSummary, deadline: Date)] {
        guard lock.enabled, rules.selectionMode == .member else { return [] }
        return weeks.compactMap { week in
            guard week.status == .selection,
                  !week.skipsSelection,
                  week.selectionDeadline == nil,
                  let deadline = DefaultSelectionLockMath.futureDeadline(
                      for: lock,
                      seasonYear: week.seasonYear,
                      weekNumber: week.weekNumber,
                      now: now
                  ) else { return nil }
            return (week, deadline)
        }
    }
}

enum DefaultSelectionLockStamp {
    static let setBy = "default"

    static func apply(to week: inout WeekSummary, lock: DefaultSelectionLock, stampedAt: Date = Date()) {
        guard lock.enabled,
              week.status == .selection,
              !week.skipsSelection,
              week.selectionMode == .member,
              week.selectionDeadline == nil,
              let deadline = DefaultSelectionLockMath.futureDeadline(
                for: lock,
                seasonYear: week.seasonYear,
                weekNumber: week.weekNumber,
                now: stampedAt
              ) else { return }
        week.selectionDeadline = deadline
        week.selectionDeadlineSetAt = stampedAt
        week.selectionDeadlineSetBy = setBy
    }
}
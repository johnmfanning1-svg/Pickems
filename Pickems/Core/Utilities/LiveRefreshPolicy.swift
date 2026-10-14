import Foundation

enum LiveRefreshPolicy {
    /// Faster polling during typical CFB kickoff windows on Saturdays and Sundays.
    static var refreshInterval: Duration {
        isGameDayWindow ? .seconds(15) : .seconds(60)
    }

    static var isGameDayWindow: Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let weekday = calendar.component(.weekday, from: Date())
        guard weekday == 1 || weekday == 7 else { return false }
        let hour = calendar.component(.hour, from: Date())
        return hour >= 10 && hour <= 23
    }

    /// Home is the only tab that polls ESPN on a timer. Pause it in the background
    /// and on every other tab. The Picks tab has its own loop and stops on disappear.
    static func shouldPollLiveScores(isHomeTab: Bool, isActive: Bool) -> Bool {
        isHomeTab && isActive
    }
}

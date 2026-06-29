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
}

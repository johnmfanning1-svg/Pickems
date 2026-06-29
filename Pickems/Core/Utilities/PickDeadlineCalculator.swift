import Foundation

enum PickDeadlineCalculator {
    static func compute(
        kickoffs: [Date],
        policy: DeadlinePolicy,
        customHour: Int,
        customMinute: Int
    ) -> Date? {
        guard let firstKickoff = kickoffs.min() else { return nil }

        switch policy {
        case .firstKickoff:
            return firstKickoff
        case .custom:
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: firstKickoff) else {
                return firstKickoff
            }
            return calendar.date(
                bySettingHour: customHour,
                minute: customMinute,
                second: 0,
                of: dayBefore
            ) ?? firstKickoff
        }
    }

    static func isPast(_ deadline: Date?) -> Bool {
        guard let deadline else { return true }
        return Date() >= deadline
    }

    static func countdownLabel(to deadline: Date) -> String {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { return "Deadline passed" }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h left"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }
}

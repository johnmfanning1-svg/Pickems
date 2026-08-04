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

    /// Nil deadline means picks remain open (not locked).
    static func isPast(_ deadline: Date?) -> Bool {
        guard let deadline else { return false }
        return Date() >= deadline
    }

    /// Absolute lock time for UI, e.g. "Sat 12:00 PM".
    static func lockTimeLabel(for deadline: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: deadline)
    }

    static func countdownLabel(to deadline: Date) -> String {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { return "Picks locked" }

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

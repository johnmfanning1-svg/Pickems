import Foundation

enum ScrimmageData {
    static let bots: [ScrimmageBot] = [
        ScrimmageBot(id: "scrimmage-bot-1", displayName: "Blitz Bot", agreesWithUserCount: 3),
        ScrimmageBot(id: "scrimmage-bot-2", displayName: "Coach Crunch", agreesWithUserCount: 2),
        ScrimmageBot(id: "scrimmage-bot-3", displayName: "Hail Mary Harry", agreesWithUserCount: 1),
    ]

    static func makeGames() -> [SlateGame] {
        let kickoffs = upcomingSaturdayKickoffs()
        return [
            SlateGame(
                id: "scrimmage-g1",
                espnEventId: "scrimmage-g1",
                homeTeamId: "scrimmage-t1",
                homeTeamName: "Gridiron State Grinders",
                homeTeamAbbreviation: "GSG",
                homeTeamLogoURL: nil,
                awayTeamId: "scrimmage-t2",
                awayTeamName: "Pigskin U Pouncers",
                awayTeamAbbreviation: "PUP",
                awayTeamLogoURL: nil,
                spread: -3.5,
                spreadTeamId: "scrimmage-t1",
                kickoff: kickoffs[0],
                status: .scheduled,
                homeScore: nil,
                awayScore: nil,
                winnerTeamId: nil
            ),
            SlateGame(
                id: "scrimmage-g2",
                espnEventId: "scrimmage-g2",
                homeTeamId: "scrimmage-t3",
                homeTeamName: "Touchdown Tech Titans",
                homeTeamAbbreviation: "TTT",
                homeTeamLogoURL: nil,
                awayTeamId: "scrimmage-t4",
                awayTeamName: "Endzone State Elk",
                awayTeamAbbreviation: "ESE",
                awayTeamLogoURL: nil,
                spread: -6.5,
                spreadTeamId: "scrimmage-t3",
                kickoff: kickoffs[1],
                status: .scheduled,
                homeScore: nil,
                awayScore: nil,
                winnerTeamId: nil
            ),
            SlateGame(
                id: "scrimmage-g3",
                espnEventId: "scrimmage-g3",
                homeTeamId: "scrimmage-t5",
                homeTeamName: "Cleat City Crushers",
                homeTeamAbbreviation: "CCC",
                homeTeamLogoURL: nil,
                awayTeamId: "scrimmage-t6",
                awayTeamName: "Snap Count Saints",
                awayTeamAbbreviation: "SCS",
                awayTeamLogoURL: nil,
                spread: -2.5,
                spreadTeamId: "scrimmage-t5",
                kickoff: kickoffs[2],
                status: .scheduled,
                homeScore: nil,
                awayScore: nil,
                winnerTeamId: nil
            ),
            SlateGame(
                id: "scrimmage-g4",
                espnEventId: "scrimmage-g4",
                homeTeamId: "scrimmage-t7",
                homeTeamName: "Turf War Warriors",
                homeTeamAbbreviation: "TWW",
                homeTeamLogoURL: nil,
                awayTeamId: "scrimmage-t8",
                awayTeamName: "Blitzkrieg Bay Bucs",
                awayTeamAbbreviation: "BBB",
                awayTeamLogoURL: nil,
                spread: -7.5,
                spreadTeamId: "scrimmage-t7",
                kickoff: kickoffs[3],
                status: .scheduled,
                homeScore: nil,
                awayScore: nil,
                winnerTeamId: nil
            ),
        ]
    }

    /// Next Saturday at noon, 3:30pm, 7pm, and 10:30pm local time.
    private static func upcomingSaturdayKickoffs() -> [Date] {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        // Gregorian: Saturday == 7. If today is Saturday, use next week.
        var daysUntilSaturday = (7 - weekday + 7) % 7
        if daysUntilSaturday == 0 {
            daysUntilSaturday = 7
        }
        let startOfToday = calendar.startOfDay(for: now)
        guard let saturday = calendar.date(byAdding: .day, value: daysUntilSaturday, to: startOfToday) else {
            return Array(repeating: now.addingTimeInterval(86_400), count: 4)
        }

        let components: [(hour: Int, minute: Int)] = [
            (12, 0),
            (15, 30),
            (19, 0),
            (22, 30),
        ]
        return components.map { hour, minute in
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: saturday) ?? saturday
        }
    }
}

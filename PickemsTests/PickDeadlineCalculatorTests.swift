import Foundation
import Testing
@testable import Pickems

struct PickDeadlineCalculatorTests {
    @Test func firstKickoffPolicyUsesEarliestKickoff() {
        let kickoffs = [
            Date(timeIntervalSince1970: 1_000_000),
            Date(timeIntervalSince1970: 900_000),
            Date(timeIntervalSince1970: 1_100_000),
        ]
        let deadline = PickDeadlineCalculator.compute(
            kickoffs: kickoffs,
            policy: .firstKickoff,
            customHour: 20,
            customMinute: 0
        )
        #expect(deadline == kickoffs.min())
    }

    @Test func customPolicyUsesDayBeforeKickoffAtConfiguredTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let kickoff = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 9,
            day: 6,
            hour: 19,
            minute: 0
        ))!

        let deadline = PickDeadlineCalculator.compute(
            kickoffs: [kickoff],
            policy: .custom,
            customHour: 20,
            customMinute: 30
        )

        let expectedDay = calendar.date(byAdding: .day, value: -1, to: kickoff)!
        let expected = calendar.date(
            bySettingHour: 20,
            minute: 30,
            second: 0,
            of: expectedDay
        )
        #expect(deadline == expected)
    }

    @Test func isPastTreatsNilAsOpen() {
        #expect(!PickDeadlineCalculator.isPast(nil))
    }

    @Test func lockTimeLabelIncludesMonthAndDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let deadline = calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 5,
            hour: 12,
            minute: 0
        ))!
        let label = PickDeadlineCalculator.lockTimeLabel(for: deadline)
        #expect(label.contains("12:00"))
        #expect(label.contains("Sep") || label.contains("9"))
        #expect(label.contains("5"))
        #expect(label.contains("PM") || label.contains("pm") || label.contains("p.m."))
    }

    @Test func countdownLabelShowsMinutesWhenUnderOneHour() {
        let deadline = Date().addingTimeInterval(45 * 60)
        let label = PickDeadlineCalculator.countdownLabel(to: deadline)
        #expect(label.contains("m left"))
    }

    @Test func rollingPolicyUsesEarliestKickoffForFirstLock() {
        let kickoffs = [
            Date(timeIntervalSince1970: 1_000_000),
            Date(timeIntervalSince1970: 900_000),
            Date(timeIntervalSince1970: 1_100_000),
        ]
        let deadline = PickDeadlineCalculator.compute(
            kickoffs: kickoffs,
            policy: .rolling,
            customHour: 20,
            customMinute: 0
        )
        #expect(deadline == kickoffs.min())
    }

    @Test func nextLockDateSkipsAlreadyLockedRollingGames() {
        let first = Date().addingTimeInterval(-60)
        let last = Date().addingTimeInterval(3600)
        let week = WeekSummary(
            id: "2026-W1",
            seasonYear: 2026,
            weekNumber: 1,
            status: .picking,
            slateSize: 2,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: first,
            pickLockMode: .rolling,
            weekLockAt: last,
            nominationCount: 2
        )
        let games = [
            SlateGame(
                id: "thu",
                espnEventId: "thu",
                homeTeamId: "h1",
                homeTeamName: "Home",
                homeTeamAbbreviation: "H1",
                homeTeamLogoURL: nil,
                awayTeamId: "a1",
                awayTeamName: "Away",
                awayTeamAbbreviation: "A1",
                awayTeamLogoURL: nil,
                spread: 3,
                spreadTeamId: "h1",
                kickoff: first,
                status: .inProgress
            ),
            SlateGame(
                id: "sun",
                espnEventId: "sun",
                homeTeamId: "h2",
                homeTeamName: "Home2",
                homeTeamAbbreviation: "H2",
                homeTeamLogoURL: nil,
                awayTeamId: "a2",
                awayTeamName: "Away2",
                awayTeamAbbreviation: "A2",
                awayTeamLogoURL: nil,
                spread: 7,
                spreadTeamId: "h2",
                kickoff: last,
                status: .scheduled
            ),
        ]
        #expect(PickDeadlineCalculator.nextLockDate(week: week, games: games) == last)
        #expect(PickDeadlineCalculator.openGameCount(week: week, games: games) == 1)
    }

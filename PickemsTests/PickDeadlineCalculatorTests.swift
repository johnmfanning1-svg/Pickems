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

    @Test func lockTimeLabelUsesWeekdayAndTime() {
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
        #expect(label.contains("PM") || label.contains("pm") || label.contains("p.m."))
    }

    @Test func countdownLabelShowsMinutesWhenUnderOneHour() {
        let deadline = Date().addingTimeInterval(45 * 60)
        let label = PickDeadlineCalculator.countdownLabel(to: deadline)
        #expect(label.contains("m left"))
    }
}

import Foundation
import Testing
@testable import Pickems

struct GameKickoffLineTests {
    @Test func includeDateAddsDateComponentAndBroadcast() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let kickoff = calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 29,
            hour: 15,
            minute: 30
        ))!

        let withDate = GameKickoffLine.make(
            kickoff: kickoff,
            broadcastLabel: "ESPN",
            includeDate: true
        )
        let timeOnly = GameKickoffLine.make(
            kickoff: kickoff,
            broadcastLabel: "ESPN",
            includeDate: false
        )
        let dateAndTime = kickoff.formatted(date: .abbreviated, time: .shortened)
        let time = kickoff.formatted(date: .omitted, time: .shortened)

        #expect(dateAndTime != time)
        #expect(withDate == "\(dateAndTime) · ESPN")
        #expect(timeOnly == "\(time) · ESPN")
        #expect(withDate != timeOnly)
        #expect(withDate.contains("ESPN"))
    }

    @Test func includeDateWithoutBroadcastIsDateAndTimeOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let kickoff = calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 5,
            hour: 12,
            minute: 0
        ))!

        let withDate = GameKickoffLine.make(
            kickoff: kickoff,
            broadcastLabel: nil,
            includeDate: true
        )
        let timeOnly = GameKickoffLine.make(
            kickoff: kickoff,
            broadcastLabel: "TBD",
            includeDate: false
        )

        #expect(withDate == kickoff.formatted(date: .abbreviated, time: .shortened))
        #expect(timeOnly == kickoff.formatted(date: .omitted, time: .shortened))
        #expect(!withDate.contains("·"))
        #expect(withDate != timeOnly)
    }
}

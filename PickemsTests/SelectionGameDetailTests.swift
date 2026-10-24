import Foundation
import Testing
@testable import Pickems

struct SelectionGameDetailTests {
    @Test func weekdayClockIsLocalDayAndTime() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let saturday = newYork.date(from: DateComponents(
            year: 2026, month: 10, day: 17, hour: 15, minute: 30
        ))!

        #expect(SelectionGameDetail.weekdayClock(kickoff: saturday, calendar: newYork) == "Sat 3:30 PM")

        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(SelectionGameDetail.weekdayClock(kickoff: saturday, calendar: losAngeles) == "Sat 12:30 PM")
    }

    @Test func weekdayClockCanChangeTheDayAcrossTimeZones() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let sundayMorningUTC = utc.date(from: DateComponents(
            year: 2026, month: 10, day: 18, hour: 0, minute: 30
        ))!

        #expect(SelectionGameDetail.weekdayClock(kickoff: sundayMorningUTC, calendar: utc) == "Sun 12:30 AM")
        #expect(SelectionGameDetail.weekdayClock(kickoff: sundayMorningUTC, calendar: newYork) == "Sat 8:30 PM")
    }

    @Test func scheduledCardShowsKickoffNetworkAndRecords() {
        let detail = SelectionGameDetail.make(
            kickoff: saturdayKickoff,
            status: .scheduled,
            broadcastLabel: "CBS",
            awayAbbreviation: "AUB",
            homeAbbreviation: "UGA",
            awayRecord: "3-2",
            homeRecord: "5-0",
            calendar: newYork
        )

        #expect(detail.headline == "Sat 3:30 PM")
        #expect(detail.network == "CBS")
        #expect(detail.records == "AUB 3-2 · UGA 5-0")
        #expect(detail.phase == .scheduled)
        #expect(detail.accessibilityLabel == "Sat 3:30 PM, CBS, AUB 3-2 · UGA 5-0")
    }

    @Test func missingNetworkAndRecordsAreOmitted() {
        let detail = SelectionGameDetail.make(
            kickoff: saturdayKickoff,
            status: .scheduled,
            broadcastLabel: " TBD ",
            awayAbbreviation: "AUB",
            homeAbbreviation: "UGA",
            awayRecord: "  ",
            homeRecord: nil,
            calendar: newYork
        )

        #expect(detail.headline == "Sat 3:30 PM")
        #expect(detail.network == nil)
        #expect(detail.records == nil)
        #expect(detail.accessibilityLabel == "Sat 3:30 PM")
    }

    @Test func oneRecordStillShowsThatTeam() {
        let detail = SelectionGameDetail.make(
            kickoff: saturdayKickoff,
            status: .scheduled,
            awayAbbreviation: "AUB",
            homeAbbreviation: "UGA",
            awayRecord: nil,
            homeRecord: "5-0",
            calendar: newYork
        )
        #expect(detail.records == "UGA 5-0")
    }

    @Test func liveScoreReplacesKickoff() {
        let detail = SelectionGameDetail.make(
            kickoff: saturdayKickoff,
            status: .inProgress,
            awayScore: 14,
            homeScore: 21,
            broadcastLabel: "CBS",
            awayAbbreviation: "AUB",
            homeAbbreviation: "UGA",
            awayRecord: "3-2",
            homeRecord: "5-0",
            calendar: newYork
        )

        #expect(detail.headline == "14-21")
        #expect(detail.phase == .live)
        #expect(!detail.headline.contains("Sat"))
        #expect(detail.network == "CBS")
        #expect(detail.records == "AUB 3-2 · UGA 5-0")
        #expect(detail.accessibilityLabel.hasPrefix("Live, AUB 14, UGA 21"))
    }

    @Test func liveWithoutScoreSaysLive() {
        let detail = SelectionGameDetail.make(
            kickoff: saturdayKickoff,
            status: .inProgress,
            calendar: newYork
        )
        #expect(detail.headline == "Live")
        #expect(detail.phase == .live)
        #expect(detail.accessibilityLabel == "Live")
    }

    @Test func finalReplacesKickoff() {
        let withScore = SelectionGameDetail.make(
            kickoff: saturdayKickoff,
            status: .final,
            awayScore: 17,
            homeScore: 31,
            calendar: newYork
        )
        #expect(withScore.headline == "Final 17-31")
        #expect(withScore.phase == .final)
        #expect(!withScore.headline.contains("Sat"))

        let withoutScore = SelectionGameDetail.make(
            kickoff: saturdayKickoff,
            status: .final,
            calendar: newYork
        )
        #expect(withoutScore.headline == "Final")
        #expect(withoutScore.phase == .final)
    }

    @Test func resolvedStatusPrefersLiveCardOverEspnFinal() {
        // A non-final live card must win — same precedence as selectionGameDetail /
        // nominationIsFinal. ESPN final alone must not override an in-progress live card.
        #expect(
            SelectionGameDetail.resolvedStatus(live: .inProgress, espn: .final) == .inProgress
        )
        #expect(
            SelectionGameDetail.resolvedStatus(live: .inProgress, espn: .final) != .final
        )
        #expect(SelectionGameDetail.resolvedStatus(live: .final, espn: .inProgress) == .final)
        #expect(SelectionGameDetail.resolvedStatus(live: nil, espn: .final) == .final)
        #expect(SelectionGameDetail.resolvedStatus(live: nil, espn: .inProgress) == .inProgress)
        #expect(SelectionGameDetail.resolvedStatus(live: nil, espn: nil) == .scheduled)
        #expect(SelectionGameDetail.resolvedStatus(live: .scheduled, espn: .final) == .scheduled)
    }

    private var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private var saturdayKickoff: Date {
        newYork.date(from: DateComponents(
            year: 2026, month: 10, day: 17, hour: 15, minute: 30
        ))!
    }
}

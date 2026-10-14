import Foundation
import Testing
@testable import Pickems

struct SelectionCardDetailTests {
    private let enUS = Locale(identifier: "en_US")
    private let eastern = TimeZone(identifier: "America/New_York")!

    /// Sat Aug 29 2026, 3:30 PM ET.
    private var kickoff: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 15, minute: 30))!
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func input(
        status: SlateGame.GameStatus = .scheduled,
        broadcast: String? = "ABC",
        records: (String, String)? = ("5-1", "4-2")
    ) -> SelectionCardDetail.Input {
        SelectionCardDetail.Input(
            kickoff: kickoff,
            status: status,
            awayScore: status == .scheduled ? nil : 17,
            homeScore: status == .scheduled ? nil : 24,
            liveClock: status == .inProgress ? "3rd 4:12" : nil,
            broadcastLabel: broadcast,
            awayAbbreviation: "UGA",
            homeAbbreviation: "BAMA",
            awayRecord: records?.0,
            homeRecord: records?.1
        )
    }

    @Test func kickoffIsShortWeekdayAndLocalTime() {
        #expect(normalized(SelectionCardDetail.kickoffText(kickoff, locale: enUS, timeZone: eastern)) == "Sat 3:30 PM")
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        #expect(normalized(SelectionCardDetail.kickoffText(kickoff, locale: enUS, timeZone: pacific)) == "Sat 12:30 PM")
    }

    @Test func scheduledShowsTimeNetworkAndRecords() {
        let line = normalized(SelectionCardDetail.line(input(), locale: enUS, timeZone: eastern))
        #expect(line == "Sat 3:30 PM · ABC · UGA 5-1, BAMA 4-2")
    }

    @Test func missingNetworkAndRecordsStayCompact() {
        let line = normalized(SelectionCardDetail.line(input(broadcast: nil, records: nil), locale: enUS, timeZone: eastern))
        #expect(line == "Sat 3:30 PM")
    }

    @Test func liveReplacesTheKickoffTime() {
        let line = SelectionCardDetail.line(input(status: .inProgress), locale: enUS, timeZone: eastern)
        #expect(line.hasPrefix("Live UGA 17–BAMA 24 · 3rd 4:12"))
        #expect(!line.contains("ABC"))
        #expect(!normalized(line).contains("3:30 PM"))
    }

    @Test func finalReplacesTheKickoffTime() {
        let line = SelectionCardDetail.line(input(status: .final, records: nil), locale: enUS, timeZone: eastern)
        #expect(line == "Final UGA 17–BAMA 24")
    }

    @Test func overallRecordPrefersTotal() {
        typealias R = ESPNScoreboardResponse.ESPNRecord
        let records = [
            R(name: "Home", type: "homerecord", summary: "3-0"),
            R(name: "overall", type: "total", summary: "5-1"),
        ]
        #expect(ESPNService.overallRecord(records) == "5-1")
        #expect(ESPNService.overallRecord(nil) == nil)
        #expect(ESPNService.overallRecord([R(name: nil, type: nil, summary: "n/a")]) == nil)
    }

    @Test func competitorDecodesRecords() throws {
        let json = #"{"id":"1","homeAway":"home","team":{"id":"333","displayName":"Alabama","abbreviation":"BAMA"},"records":[{"name":"overall","type":"total","summary":"4-2"}]}"#
        let competitor = try JSONDecoder().decode(ESPNScoreboardResponse.ESPNCompetitor.self, from: Data(json.utf8))
        #expect(ESPNService.overallRecord(competitor.records) == "4-2")
    }
}

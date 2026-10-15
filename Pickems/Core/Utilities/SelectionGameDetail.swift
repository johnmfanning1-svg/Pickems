import Foundation

/// Trailing copy for a Selections card: local kickoff, then network and records
/// when ESPN already sent them. Live and final games replace the kickoff.
struct SelectionGameDetail: Equatable {
    enum Phase: Equatable {
        case scheduled
        case live
        case final
    }

    var headline: String
    var network: String?
    var records: String?
    var phase: Phase

    var accessibilityLabel: String {
        [headline, network, records]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    static func make(
        kickoff: Date,
        status: SlateGame.GameStatus,
        awayScore: Int? = nil,
        homeScore: Int? = nil,
        broadcastLabel: String? = nil,
        awayAbbreviation: String = "",
        homeAbbreviation: String = "",
        awayRecord: String? = nil,
        homeRecord: String? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SelectionGameDetail {
        let phase: Phase
        let headline: String
        switch status {
        case .scheduled:
            phase = .scheduled
            headline = weekdayClock(kickoff: kickoff, calendar: calendar)
        case .inProgress:
            phase = .live
            if let awayScore, let homeScore {
                headline = "\(awayScore)-\(homeScore)"
            } else {
                headline = "Live"
            }
        case .final:
            phase = .final
            if let awayScore, let homeScore {
                headline = "Final \(awayScore)-\(homeScore)"
            } else {
                headline = "Final"
            }
        }

        return SelectionGameDetail(
            headline: headline,
            network: networkLine(broadcastLabel),
            records: recordsLine(
                awayAbbreviation: awayAbbreviation,
                awayRecord: awayRecord,
                homeAbbreviation: homeAbbreviation,
                homeRecord: homeRecord
            ),
            phase: phase
        )
    }

    /// `Sat 3:30 PM` in `calendar`'s time zone.
    /// `en_US_POSIX` keeps the 12-hour clock when the device is set to 24-hour time.
    static func weekdayClock(
        kickoff: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: kickoff)
    }

    /// National network when ESPN sent one. Empty and `TBD` stay hidden.
    static func networkLine(_ broadcastLabel: String?) -> String? {
        guard let broadcastLabel else { return nil }
        let trimmed = broadcastLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("TBD") != .orderedSame else { return nil }
        return trimmed
    }

    /// `AUB 3-2 · UGA 5-0`. Either side is omitted when ESPN has no overall record.
    static func recordsLine(
        awayAbbreviation: String,
        awayRecord: String?,
        homeAbbreviation: String,
        homeRecord: String?
    ) -> String? {
        let parts = [
            recordPiece(abbreviation: awayAbbreviation, record: awayRecord),
            recordPiece(abbreviation: homeAbbreviation, record: homeRecord)
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func recordPiece(abbreviation: String, record: String?) -> String? {
        guard let record else { return nil }
        let summary = record.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        let name = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? summary : "\(name) \(summary)"
    }
}

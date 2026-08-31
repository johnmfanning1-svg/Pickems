import Foundation

struct ESPNConference: Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String
}

enum ESPNConferenceCatalog {
    /// FBS conference groups, ESPN group ids. Order = display order.
    static let fbs: [ESPNConference] = [
        ESPNConference(id: "8", name: "SEC", shortName: "SEC"),
        ESPNConference(id: "5", name: "Big Ten", shortName: "B1G"),
        ESPNConference(id: "4", name: "Big 12", shortName: "Big 12"),
        ESPNConference(id: "1", name: "ACC", shortName: "ACC"),
        ESPNConference(id: "9", name: "Pac-12", shortName: "Pac-12"),
        ESPNConference(id: "151", name: "American Athletic", shortName: "AAC"),
        ESPNConference(id: "17", name: "Mountain West", shortName: "MWC"),
        ESPNConference(id: "37", name: "Sun Belt", shortName: "Sun Belt"),
        ESPNConference(id: "15", name: "Mid-American", shortName: "MAC"),
        ESPNConference(id: "12", name: "Conference USA", shortName: "C-USA"),
        ESPNConference(id: "18", name: "FBS Independents", shortName: "Ind"),
    ]

    /// Power 4 conference ESPN ids: SEC, Big Ten, Big 12, ACC.
    static let power4Ids: Set<String> = ["8", "5", "4", "1"]

    static var power4: [ESPNConference] {
        fbs.filter { power4Ids.contains($0.id) }
    }

    static func isPower4(_ conferenceId: String?) -> Bool {
        guard let conferenceId else { return false }
        return power4Ids.contains(conferenceId)
    }

    static func conference(id: String?) -> ESPNConference? {
        guard let id else { return nil }
        return fbs.first { $0.id == id }
    }
}

enum GameSlateFilter: Hashable {
    case all, top25
    case conference(id: String)
}

/// Filters for the Home "CFB This Week" scoreboard. Defaults to Top 25.
enum HomeScoreboardFilter: Hashable {
    case power4
    case top25
    case all
    case myPicks
    case groupSlate
    case conference(id: String)

    static let `default`: HomeScoreboardFilter = .top25

    /// Leading chips, left to right. Individual conferences follow from the FBS catalog.
    static let primaryChips: [HomeScoreboardFilter] = [
        .top25, .myPicks, .groupSlate, .all, .power4
    ]

    var title: String {
        switch self {
        case .power4: return "Power 4"
        case .top25: return "Top 25"
        case .all: return "All"
        case .myPicks: return "My Picks"
        case .groupSlate: return "Group"
        case .conference(let id):
            return ESPNConferenceCatalog.conference(id: id)?.shortName ?? "Conf"
        }
    }
}

enum HomeScoreboardDisplay {
    static let previewLimit = 12

    static func games(_ filtered: [ESPNLiveGameCard], filter: HomeScoreboardFilter?) -> [ESPNLiveGameCard] {
        switch filter {
        case .myPicks, .groupSlate:
            return filtered
        default:
            return Array(filtered.prefix(previewLimit))
        }
    }
}

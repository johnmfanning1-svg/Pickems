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

    static func conference(id: String?) -> ESPNConference? {
        guard let id else { return nil }
        return fbs.first { $0.id == id }
    }
}

enum GameSlateFilter: Hashable {
    case all, top25
    case conference(id: String)
}

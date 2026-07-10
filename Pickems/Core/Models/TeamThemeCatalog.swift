import Foundation

/// Curated CFB team colors chosen for contrast on Pickems' dark UI.
enum TeamThemeCatalog {
    static let teams: [FavoriteTeam] = [
        // SEC
        FavoriteTeam(id: "333", name: "Alabama", abbreviation: "ALA", primaryHex: "#9E1B32", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "8", name: "Arkansas", abbreviation: "ARK", primaryHex: "#9D2235", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "2", name: "Auburn", abbreviation: "AUB", primaryHex: "#0C2340", secondaryHex: "#E87722"),
        FavoriteTeam(id: "57", name: "Florida", abbreviation: "FLA", primaryHex: "#0021A5", secondaryHex: "#FA4616"),
        FavoriteTeam(id: "61", name: "Georgia", abbreviation: "UGA", primaryHex: "#BA0C2F", secondaryHex: "#000000"),
        FavoriteTeam(id: "96", name: "Kentucky", abbreviation: "UK", primaryHex: "#0033A0", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "99", name: "LSU", abbreviation: "LSU", primaryHex: "#461D7C", secondaryHex: "#FDD023"),
        FavoriteTeam(id: "142", name: "Mississippi State", abbreviation: "MSST", primaryHex: "#5D1725", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "143", name: "Missouri", abbreviation: "MIZ", primaryHex: "#F1B82D", secondaryHex: "#000000"),
        FavoriteTeam(id: "145", name: "Ole Miss", abbreviation: "MISS", primaryHex: "#CE1126", secondaryHex: "#14213D"),
        FavoriteTeam(id: "201", name: "Oklahoma", abbreviation: "OU", primaryHex: "#841617", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "2579", name: "South Carolina", abbreviation: "SC", primaryHex: "#73000A", secondaryHex: "#000000"),
        FavoriteTeam(id: "263", name: "Tennessee", abbreviation: "TENN", primaryHex: "#FF8200", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "251", name: "Texas", abbreviation: "TEX", primaryHex: "#BF5700", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "245", name: "Texas A&M", abbreviation: "TA&M", primaryHex: "#500000", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "238", name: "Vanderbilt", abbreviation: "VAN", primaryHex: "#866D4B", secondaryHex: "#000000"),

        // Big Ten
        FavoriteTeam(id: "356", name: "Illinois", abbreviation: "ILL", primaryHex: "#E84A27", secondaryHex: "#13294B"),
        FavoriteTeam(id: "84", name: "Indiana", abbreviation: "IU", primaryHex: "#990000", secondaryHex: "#EEEDEB"),
        FavoriteTeam(id: "2294", name: "Iowa", abbreviation: "IOWA", primaryHex: "#FFCD00", secondaryHex: "#000000"),
        FavoriteTeam(id: "120", name: "Maryland", abbreviation: "MD", primaryHex: "#E03A3E", secondaryHex: "#FFD520"),
        FavoriteTeam(id: "130", name: "Michigan", abbreviation: "MICH", primaryHex: "#00274C", secondaryHex: "#FFCB05"),
        FavoriteTeam(id: "127", name: "Michigan State", abbreviation: "MSU", primaryHex: "#18453B", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "135", name: "Minnesota", abbreviation: "MINN", primaryHex: "#7A0019", secondaryHex: "#FFCC33"),
        FavoriteTeam(id: "158", name: "Nebraska", abbreviation: "NEB", primaryHex: "#E41C38", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "77", name: "Northwestern", abbreviation: "NU", primaryHex: "#4E2A84", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "194", name: "Ohio State", abbreviation: "OSU", primaryHex: "#BA0C2F", secondaryHex: "#666666"),
        FavoriteTeam(id: "2483", name: "Oregon", abbreviation: "ORE", primaryHex: "#154733", secondaryHex: "#FEE123"),
        FavoriteTeam(id: "213", name: "Penn State", abbreviation: "PSU", primaryHex: "#041E42", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "2509", name: "Purdue", abbreviation: "PUR", primaryHex: "#CEB888", secondaryHex: "#000000"),
        FavoriteTeam(id: "164", name: "Rutgers", abbreviation: "RUTG", primaryHex: "#CC0033", secondaryHex: "#5F6A72"),
        FavoriteTeam(id: "26", name: "UCLA", abbreviation: "UCLA", primaryHex: "#2D68C4", secondaryHex: "#F2A900"),
        FavoriteTeam(id: "30", name: "USC", abbreviation: "USC", primaryHex: "#990000", secondaryHex: "#FFC72C"),
        FavoriteTeam(id: "264", name: "Washington", abbreviation: "WASH", primaryHex: "#4B2E83", secondaryHex: "#B7A57A"),
        FavoriteTeam(id: "275", name: "Wisconsin", abbreviation: "WISC", primaryHex: "#C5050C", secondaryHex: "#FFFFFF"),

        // ACC
        FavoriteTeam(id: "103", name: "Boston College", abbreviation: "BC", primaryHex: "#98002E", secondaryHex: "#110E0E"),
        FavoriteTeam(id: "228", name: "Clemson", abbreviation: "CLEM", primaryHex: "#F56600", secondaryHex: "#522D80"),
        FavoriteTeam(id: "150", name: "Duke", abbreviation: "DUKE", primaryHex: "#003087", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "52", name: "Florida State", abbreviation: "FSU", primaryHex: "#782F40", secondaryHex: "#CEB888"),
        FavoriteTeam(id: "59", name: "Georgia Tech", abbreviation: "GT", primaryHex: "#B3A369", secondaryHex: "#003057"),
        FavoriteTeam(id: "97", name: "Louisville", abbreviation: "LOU", primaryHex: "#AD0000", secondaryHex: "#000000"),
        FavoriteTeam(id: "2390", name: "Miami", abbreviation: "MIA", primaryHex: "#F47321", secondaryHex: "#005030"),
        FavoriteTeam(id: "153", name: "North Carolina", abbreviation: "UNC", primaryHex: "#7BAFD4", secondaryHex: "#13294B"),
        FavoriteTeam(id: "152", name: "NC State", abbreviation: "NCST", primaryHex: "#CC0000", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "221", name: "Pittsburgh", abbreviation: "PITT", primaryHex: "#003594", secondaryHex: "#FFB81C"),
        FavoriteTeam(id: "183", name: "Syracuse", abbreviation: "SYR", primaryHex: "#F76900", secondaryHex: "#000E54"),
        FavoriteTeam(id: "258", name: "Virginia", abbreviation: "UVA", primaryHex: "#232D4B", secondaryHex: "#F84C1E"),
        FavoriteTeam(id: "259", name: "Virginia Tech", abbreviation: "VT", primaryHex: "#861F41", secondaryHex: "#E5751F"),
        FavoriteTeam(id: "154", name: "Wake Forest", abbreviation: "WAKE", primaryHex: "#9E7E38", secondaryHex: "#000000"),
        FavoriteTeam(id: "25", name: "California", abbreviation: "CAL", primaryHex: "#003262", secondaryHex: "#FDB515"),
        FavoriteTeam(id: "24", name: "Stanford", abbreviation: "STAN", primaryHex: "#8C1515", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "2534", name: "SMU", abbreviation: "SMU", primaryHex: "#C8102E", secondaryHex: "#0033A0"),

        // Big 12
        FavoriteTeam(id: "12", name: "Arizona", abbreviation: "ARIZ", primaryHex: "#CC0033", secondaryHex: "#003366"),
        FavoriteTeam(id: "9", name: "Arizona State", abbreviation: "ASU", primaryHex: "#8C1D40", secondaryHex: "#FFC627"),
        FavoriteTeam(id: "239", name: "Baylor", abbreviation: "BAY", primaryHex: "#154734", secondaryHex: "#FFB81C"),
        FavoriteTeam(id: "2132", name: "Cincinnati", abbreviation: "CIN", primaryHex: "#E00122", secondaryHex: "#000000"),
        FavoriteTeam(id: "38", name: "Colorado", abbreviation: "COLO", primaryHex: "#CFB87C", secondaryHex: "#000000"),
        FavoriteTeam(id: "248", name: "Houston", abbreviation: "HOU", primaryHex: "#C8102E", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "66", name: "Iowa State", abbreviation: "ISU", primaryHex: "#C8102E", secondaryHex: "#F1BE48"),
        FavoriteTeam(id: "2305", name: "Kansas", abbreviation: "KU", primaryHex: "#0051BA", secondaryHex: "#E8000D"),
        FavoriteTeam(id: "2306", name: "Kansas State", abbreviation: "KSU", primaryHex: "#512888", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "197", name: "Oklahoma State", abbreviation: "OKST", primaryHex: "#FF7300", secondaryHex: "#000000"),
        FavoriteTeam(id: "2628", name: "TCU", abbreviation: "TCU", primaryHex: "#4D1979", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "2641", name: "Texas Tech", abbreviation: "TTU", primaryHex: "#CC0000", secondaryHex: "#000000"),
        FavoriteTeam(id: "254", name: "Utah", abbreviation: "UTAH", primaryHex: "#CC0000", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "2116", name: "UCF", abbreviation: "UCF", primaryHex: "#BA9B37", secondaryHex: "#000000"),
        FavoriteTeam(id: "98", name: "West Virginia", abbreviation: "WVU", primaryHex: "#002855", secondaryHex: "#EAAA00"),
        FavoriteTeam(id: "252", name: "BYU", abbreviation: "BYU", primaryHex: "#002E5D", secondaryHex: "#FFFFFF"),

        // Independents & others
        FavoriteTeam(id: "87", name: "Notre Dame", abbreviation: "ND", primaryHex: "#0C2340", secondaryHex: "#C99700"),
        FavoriteTeam(id: "349", name: "Army", abbreviation: "ARMY", primaryHex: "#D4BF91", secondaryHex: "#000000"),
        FavoriteTeam(id: "2426", name: "Navy", abbreviation: "NAVY", primaryHex: "#00205B", secondaryHex: "#C5B783"),
        FavoriteTeam(id: "2005", name: "Air Force", abbreviation: "AFA", primaryHex: "#003087", secondaryHex: "#8A8D8F"),
        FavoriteTeam(id: "68", name: "Boise State", abbreviation: "BSU", primaryHex: "#0033A0", secondaryHex: "#D64309"),
        FavoriteTeam(id: "204", name: "Oregon State", abbreviation: "ORST", primaryHex: "#DC4405", secondaryHex: "#000000"),
        FavoriteTeam(id: "265", name: "Washington State", abbreviation: "WSU", primaryHex: "#981E32", secondaryHex: "#5E6A71"),
        FavoriteTeam(id: "21", name: "San Diego State", abbreviation: "SDSU", primaryHex: "#A89968", secondaryHex: "#000000"),
        FavoriteTeam(id: "16", name: "Fresno State", abbreviation: "FRES", primaryHex: "#DB0032", secondaryHex: "#002E6D"),
        FavoriteTeam(id: "328", name: "Utah State", abbreviation: "USU", primaryHex: "#0F2439", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "41", name: "Connecticut", abbreviation: "CONN", primaryHex: "#000E2F", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "151", name: "East Carolina", abbreviation: "ECU", primaryHex: "#592A8A", secondaryHex: "#FDC82F"),
        FavoriteTeam(id: "58", name: "South Florida", abbreviation: "USF", primaryHex: "#006747", secondaryHex: "#CFC493"),
        FavoriteTeam(id: "218", name: "Temple", abbreviation: "TEM", primaryHex: "#9D2235", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "2226", name: "Florida Atlantic", abbreviation: "FAU", primaryHex: "#003366", secondaryHex: "#CC0000"),
        FavoriteTeam(id: "2229", name: "Florida International", abbreviation: "FIU", primaryHex: "#081E3F", secondaryHex: "#B6862C"),
        FavoriteTeam(id: "249", name: "North Texas", abbreviation: "UNT", primaryHex: "#00853E", secondaryHex: "#FFFFFF"),
        FavoriteTeam(id: "202", name: "Tulsa", abbreviation: "TLSA", primaryHex: "#002D72", secondaryHex: "#C6AA76"),
    ]

    /// Deduplicated by id, preferring the first occurrence.
    private static var uniqueTeams: [FavoriteTeam] {
        var seen = Set<String>()
        return teams.filter { seen.insert($0.id).inserted }
    }

    static var sortedTeams: [FavoriteTeam] {
        uniqueTeams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func team(id: String?) -> FavoriteTeam? {
        guard let id else { return nil }
        return uniqueTeams.first { $0.id == id }
    }

    static func team(matching query: String) -> [FavoriteTeam] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sortedTeams }
        return sortedTeams.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.abbreviation.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static func palette(for teamId: String?) -> ThemePalette {
        guard let team = team(id: teamId) else { return .pickemsDefault }
        return .from(team: team)
    }

    static func palette(for profile: UserProfile?) -> ThemePalette {
        palette(for: profile?.favoriteTeamId)
    }
}

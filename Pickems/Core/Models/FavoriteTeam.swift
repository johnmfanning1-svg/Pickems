import Foundation
import SwiftUI

struct FavoriteTeam: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var abbreviation: String
    var primaryHex: String
    var secondaryHex: String
    var logoURL: String?

    var primaryColor: Color { PickemsColors.color(from: primaryHex) }
    var secondaryColor: Color { PickemsColors.color(from: secondaryHex) }

    var resolvedLogoURL: String {
        logoURL ?? "https://a.espncdn.com/i/teamlogos/ncaa/500/\(id).png"
    }
}

struct ThemePalette: Equatable {
    var accent: Color
    var accentSecondary: Color
    var atmospheric: Color
    var favoriteTeamId: String?
    var favoriteTeamName: String?
    var favoriteTeamAbbreviation: String?
    var favoriteTeamLogoURL: String?

    static let pickemsDefault = ThemePalette(
        accent: Color(red: 0.86, green: 0.15, blue: 0.15),
        accentSecondary: Color(red: 0.65, green: 0.10, blue: 0.10),
        atmospheric: Color(red: 0.86, green: 0.15, blue: 0.15),
        favoriteTeamId: nil,
        favoriteTeamName: nil,
        favoriteTeamAbbreviation: nil,
        favoriteTeamLogoURL: nil
    )

    static func from(team: FavoriteTeam) -> ThemePalette {
        ThemePalette(
            accent: team.primaryColor,
            accentSecondary: team.secondaryColor,
            atmospheric: team.primaryColor,
            favoriteTeamId: team.id,
            favoriteTeamName: team.name,
            favoriteTeamAbbreviation: team.abbreviation,
            favoriteTeamLogoURL: team.resolvedLogoURL
        )
    }
}

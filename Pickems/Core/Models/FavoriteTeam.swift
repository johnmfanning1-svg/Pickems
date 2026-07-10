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
    /// Readable accent for text, icons, tints, and strokes on the dark app background.
    var accent: Color
    var accentSecondary: Color
    /// Label/icon color for solid fills painted with `accent` (white or near-black).
    var onAccent: Color
    /// Low-opacity brand wash — may stay dark; not used for body text.
    var atmospheric: Color
    var favoriteTeamId: String?
    var favoriteTeamName: String?
    var favoriteTeamAbbreviation: String?
    var favoriteTeamLogoURL: String?

    static let pickemsDefault = ThemePalette(
        accent: Color(red: 0.86, green: 0.15, blue: 0.15),
        accentSecondary: Color(red: 0.65, green: 0.10, blue: 0.10),
        onAccent: .white,
        atmospheric: Color(red: 0.86, green: 0.15, blue: 0.15),
        favoriteTeamId: nil,
        favoriteTeamName: nil,
        favoriteTeamAbbreviation: nil,
        favoriteTeamLogoURL: nil
    )

    static func from(team: FavoriteTeam) -> ThemePalette {
        let background = ColorContrast.appBackground
        let primary = ColorContrast.RGB.from(hex: team.primaryHex)
        let secondary = ColorContrast.RGB.from(hex: team.secondaryHex)

        // Prefer the team color that already reads on dark UI (Auburn orange over navy).
        let accentRGB = ColorContrast.accessibleAccent(
            candidates: [primary, secondary],
            against: background
        )
        let secondaryCandidate = accentRGB == primary ? secondary : primary
        let accentSecondaryRGB = ColorContrast.accessibleAccent(
            candidates: [secondaryCandidate, secondary, primary],
            against: background
        )
        let onAccentRGB = ColorContrast.onAccent(for: accentRGB)

        return ThemePalette(
            accent: accentRGB.color,
            accentSecondary: accentSecondaryRGB.color,
            onAccent: onAccentRGB.color,
            atmospheric: team.primaryColor,
            favoriteTeamId: team.id,
            favoriteTeamName: team.name,
            favoriteTeamAbbreviation: team.abbreviation,
            favoriteTeamLogoURL: team.resolvedLogoURL
        )
    }
}

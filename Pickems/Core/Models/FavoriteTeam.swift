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
    /// Team accent. Dark mode is the color chosen for the dark surface; light mode is that same hue darkened until it reads.
    var accent: Color
    var accentSecondary: Color
    /// Label/icon color for solid fills painted with `accent` (white or near-black).
    var onAccent: Color
    /// Low-opacity brand wash — the raw team color, not the contrast-adjusted accent.
    var atmospheric: Color
    var favoriteTeamId: String?
    var favoriteTeamName: String?
    var favoriteTeamAbbreviation: String?
    var favoriteTeamLogoURL: String?
    var accentDarkRGB: ColorContrast.RGB
    var accentLightRGB: ColorContrast.RGB
    var accentSecondaryDarkRGB: ColorContrast.RGB
    var accentSecondaryLightRGB: ColorContrast.RGB
    var onAccentDarkRGB: ColorContrast.RGB
    var onAccentLightRGB: ColorContrast.RGB

    static func == (lhs: ThemePalette, rhs: ThemePalette) -> Bool {
        lhs.accentDarkRGB == rhs.accentDarkRGB
            && lhs.accentLightRGB == rhs.accentLightRGB
            && lhs.accentSecondaryDarkRGB == rhs.accentSecondaryDarkRGB
            && lhs.accentSecondaryLightRGB == rhs.accentSecondaryLightRGB
            && lhs.onAccentDarkRGB == rhs.onAccentDarkRGB
            && lhs.onAccentLightRGB == rhs.onAccentLightRGB
            && lhs.favoriteTeamId == rhs.favoriteTeamId
            && lhs.favoriteTeamName == rhs.favoriteTeamName
            && lhs.favoriteTeamAbbreviation == rhs.favoriteTeamAbbreviation
            && lhs.favoriteTeamLogoURL == rhs.favoriteTeamLogoURL
    }

    static let pickemsDefault: ThemePalette = {
        let accentDark = PickemsSurfaces.dark.accent
        let accentLight = PickemsSurfaces.light.accent
        let secondaryDark = PickemsSurfaces.dark.accentSecondary
        let secondaryLight = PickemsSurfaces.light.accentSecondary
        let onDark = ColorContrast.onAccent(for: accentDark)
        let onLight = ColorContrast.onAccent(for: accentLight)
        return ThemePalette(
            accent: ColorContrast.dynamicColor(light: accentLight, dark: accentDark),
            accentSecondary: ColorContrast.dynamicColor(light: secondaryLight, dark: secondaryDark),
            onAccent: ColorContrast.dynamicColor(light: onLight, dark: onDark),
            atmospheric: accentDark.color,
            favoriteTeamId: nil,
            favoriteTeamName: nil,
            favoriteTeamAbbreviation: nil,
            favoriteTeamLogoURL: nil,
            accentDarkRGB: accentDark,
            accentLightRGB: accentLight,
            accentSecondaryDarkRGB: secondaryDark,
            accentSecondaryLightRGB: secondaryLight,
            onAccentDarkRGB: onDark,
            onAccentLightRGB: onLight
        )
    }()

    static func from(team: FavoriteTeam) -> ThemePalette {
        let background = ColorContrast.appBackground
        let primary = ColorContrast.RGB.from(hex: team.primaryHex)
        let secondary = ColorContrast.RGB.from(hex: team.secondaryHex)

        // Prefer the team color that already reads on dark UI (Auburn orange over navy).
        // Light mode darkens that chosen color; it does not switch to the other school color.
        let accentDark = ColorContrast.accessibleAccent(
            candidates: [primary, secondary],
            against: background
        )
        let accentLight = ColorContrast.darkenedUntilReadable(
            accentDark,
            against: ColorContrast.lightAppBackground
        )
        let secondaryCandidate = accentDark == primary ? secondary : primary
        let accentSecondaryDark = ColorContrast.accessibleAccent(
            candidates: [secondaryCandidate, secondary, primary],
            against: background
        )
        let accentSecondaryLight = ColorContrast.darkenedUntilReadable(
            accentSecondaryDark,
            against: ColorContrast.lightAppBackground
        )
        let onDark = ColorContrast.onAccent(for: accentDark)
        let onLight = ColorContrast.onAccent(for: accentLight)

        return ThemePalette(
            accent: ColorContrast.dynamicColor(light: accentLight, dark: accentDark),
            accentSecondary: ColorContrast.dynamicColor(light: accentSecondaryLight, dark: accentSecondaryDark),
            onAccent: ColorContrast.dynamicColor(light: onLight, dark: onDark),
            atmospheric: team.primaryColor,
            favoriteTeamId: team.id,
            favoriteTeamName: team.name,
            favoriteTeamAbbreviation: team.abbreviation,
            favoriteTeamLogoURL: team.resolvedLogoURL,
            accentDarkRGB: accentDark,
            accentLightRGB: accentLight,
            accentSecondaryDarkRGB: accentSecondaryDark,
            accentSecondaryLightRGB: accentSecondaryLight,
            onAccentDarkRGB: onDark,
            onAccentLightRGB: onLight
        )
    }
}

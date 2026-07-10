import SwiftUI

@MainActor
@Observable
final class AppTheme {
    var palette: ThemePalette = .pickemsDefault

    func sync(from profile: UserProfile?) {
        let next = TeamThemeCatalog.palette(for: profile)
        guard next != palette else { return }
        palette = next
        PickemsTheme.apply(palette: next)
        if let teamId = next.favoriteTeamId, let team = TeamThemeCatalog.team(id: teamId) {
            let background = ColorContrast.appBackground
            let primary = ColorContrast.RGB.from(hex: team.primaryHex)
            let secondary = ColorContrast.RGB.from(hex: team.secondaryHex)
            let chosen = ColorContrast.accessibleAccent(candidates: [primary, secondary], against: background)
            AppLog.info(AppLog.session, "theme applied", metadata: [
                "team_id": teamId,
                "team": team.abbreviation,
                "accent_hex": chosen.hex,
                "accent_contrast": String(format: "%.2f", ColorContrast.contrastRatio(chosen, background)),
                "primary_hex": team.primaryHex,
                "secondary_hex": team.secondaryHex,
            ])
        }
    }

    func apply(team: FavoriteTeam?) {
        if let team {
            palette = .from(team: team)
            let background = ColorContrast.appBackground
            let primary = ColorContrast.RGB.from(hex: team.primaryHex)
            let secondary = ColorContrast.RGB.from(hex: team.secondaryHex)
            let chosen = ColorContrast.accessibleAccent(candidates: [primary, secondary], against: background)
            AppLog.info(AppLog.session, "theme applied", metadata: [
                "team_id": team.id,
                "team": team.abbreviation,
                "accent_hex": chosen.hex,
                "accent_contrast": String(format: "%.2f", ColorContrast.contrastRatio(chosen, background)),
                "primary_hex": team.primaryHex,
                "secondary_hex": team.secondaryHex,
            ])
        } else {
            palette = .pickemsDefault
            AppLog.info(AppLog.session, "theme applied", metadata: ["team": "default"])
        }
        PickemsTheme.apply(palette: palette)
    }
}

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.pickemsDefault
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

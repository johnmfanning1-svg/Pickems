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
    }

    func apply(team: FavoriteTeam?) {
        if let team {
            palette = .from(team: team)
        } else {
            palette = .pickemsDefault
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

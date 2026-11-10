import SwiftUI
import UIKit

enum PickemsColors {
    static let background = adaptive(\.background)
    static let cardBackground = adaptive(\.cardBackground)
    static let defaultAccent = adaptive(\.accent)
    static let defaultAccentSecondary = adaptive(\.accentSecondary)
    static let accent = defaultAccent
    static let accentSecondary = defaultAccentSecondary
    static let textPrimary = adaptive(\.textPrimary)
    static let textSecondary = adaptive(\.textSecondary)
    static let success = adaptive(\.success)
    static let warning = adaptive(\.warning)
    /// Live pick currently covering the spread.
    static let covering = adaptive(\.covering)
    /// Final loss / brand red already used as `accent`.
    static let lost = adaptive(\.lost)
    /// Final push — landed exactly on the spread. Distinct from pending (unfilled card).
    static let push = adaptive(\.push)

    /// Ink on status fills. Dark mode keeps the chip colors the board already used.
    static let onSuccess = ink(light: PickemsSurfaces.light.success, dark: .init(r: 0, g: 0, b: 0))
    static let onWarning = ink(light: PickemsSurfaces.light.warning, dark: .init(r: 0, g: 0, b: 0))
    static let onCovering = ink(light: PickemsSurfaces.light.covering, dark: .init(r: 1, g: 1, b: 1))
    static let onLost = ink(light: PickemsSurfaces.light.lost, dark: .init(r: 1, g: 1, b: 1))
    static let onPush = ink(light: PickemsSurfaces.light.push, dark: .init(r: 1, g: 1, b: 1))

    /// Hairlines that were white-on-dark. Light mode uses black at a similar strength.
    static let hairlineSubtle = hairline(lightAlpha: 0.10, darkAlpha: 0.06)
    static let hairline = hairline(lightAlpha: 0.12, darkAlpha: 0.08)
    static let hairlineStrong = hairline(lightAlpha: 0.18, darkAlpha: 0.14)
    static let separator = hairline(lightAlpha: 0.16, darkAlpha: 0.18)
    static let ring = hairline(lightAlpha: 0.22, darkAlpha: 0.25)

    static let backgroundUIColor = ColorContrast.uiColor(
        light: PickemsSurfaces.light.background,
        dark: PickemsSurfaces.dark.background
    )
    static let textPrimaryUIColor = ColorContrast.uiColor(
        light: PickemsSurfaces.light.textPrimary,
        dark: PickemsSurfaces.dark.textPrimary
    )

    static let avatarPalette: [Color] = [
        Color(red: 0.86, green: 0.15, blue: 0.15),
        Color(red: 0.20, green: 0.45, blue: 0.85),
        Color(red: 0.15, green: 0.65, blue: 0.45),
        Color(red: 0.85, green: 0.55, blue: 0.10),
        Color(red: 0.55, green: 0.30, blue: 0.75),
        Color(red: 0.30, green: 0.70, blue: 0.80),
    ]

    private static func adaptive(_ key: KeyPath<PickemsSurfacePalette, ColorContrast.RGB>) -> Color {
        ColorContrast.dynamicColor(
            light: PickemsSurfaces.light[keyPath: key],
            dark: PickemsSurfaces.dark[keyPath: key]
        )
    }

    private static func ink(light fill: ColorContrast.RGB, dark: ColorContrast.RGB) -> Color {
        ColorContrast.dynamicColor(
            light: ColorContrast.onAccent(for: fill),
            dark: dark
        )
    }

    private static func hairline(lightAlpha: Double, darkAlpha: Double) -> Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(white: 1, alpha: darkAlpha)
            }
            return UIColor(white: 0, alpha: lightAlpha)
        })
    }

    static func color(from hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    static func hex(from color: Color) -> String {
        guard let components = color.cgColor?.components, components.count >= 3 else {
            return "#DC2626"
        }
        return String(format: "#%02X%02X%02X",
                      Int(components[0] * 255),
                      Int(components[1] * 255),
                      Int(components[2] * 255))
    }
}

struct PickemsTheme {
    static func apply(palette: ThemePalette = .pickemsDefault) {
        let accent = ColorContrast.uiColor(light: palette.accentLightRGB, dark: palette.accentDarkRGB)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = PickemsColors.backgroundUIColor
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = accent

        // Transparent nav bar so each screen's atmospheric background shows through.
        // The old opaque near-black bar read as an inconsistent "pinned black chrome"
        // strip on top of the gradient screens (worse under Liquid Glass on iOS 26).
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = .clear
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [.foregroundColor: PickemsColors.textPrimaryUIColor]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: PickemsColors.textPrimaryUIColor]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = accent
    }
}

struct PickemsAtmosphericBackground: View {
    var palette: ThemePalette = .pickemsDefault
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PickemsColors.background
            LinearGradient(
                colors: [
                    palette.atmospheric.opacity(colorScheme == .dark ? 0.28 : 0.16),
                    palette.atmospheric.opacity(colorScheme == .dark ? 0.08 : 0.05),
                    PickemsColors.background,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

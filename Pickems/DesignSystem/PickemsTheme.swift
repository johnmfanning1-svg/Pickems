import SwiftUI

enum PickemsColors {
    static let background = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let cardBackground = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let defaultAccent = Color(red: 0.86, green: 0.15, blue: 0.15)
    static let defaultAccentSecondary = Color(red: 0.65, green: 0.10, blue: 0.10)
    static let accent = defaultAccent
    static let accentSecondary = defaultAccentSecondary
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let success = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let warning = Color(red: 0.95, green: 0.75, blue: 0.20)

    static let avatarPalette: [Color] = [
        Color(red: 0.86, green: 0.15, blue: 0.15),
        Color(red: 0.20, green: 0.45, blue: 0.85),
        Color(red: 0.15, green: 0.65, blue: 0.45),
        Color(red: 0.85, green: 0.55, blue: 0.10),
        Color(red: 0.55, green: 0.30, blue: 0.75),
        Color(red: 0.30, green: 0.70, blue: 0.80),
    ]

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
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIKitColor(PickemsColors.background)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = UIKitColor(palette.accent)

        // Transparent nav bar so each screen's atmospheric background shows through.
        // The old opaque near-black bar read as an inconsistent "pinned black chrome"
        // strip on top of the gradient screens (worse under Liquid Glass on iOS 26).
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = .clear
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIKitColor(palette.accent)
    }

    private static func UIKitColor(_ color: Color) -> UIColor {
        UIColor(color)
    }
}

struct PickemsAtmosphericBackground: View {
    var palette: ThemePalette = .pickemsDefault

    var body: some View {
        ZStack {
            PickemsColors.background
            LinearGradient(
                colors: [
                    palette.atmospheric.opacity(0.28),
                    palette.atmospheric.opacity(0.08),
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

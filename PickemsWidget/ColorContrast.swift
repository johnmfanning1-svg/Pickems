import Foundation
import SwiftUI
import UIKit

/// WCAG-oriented contrast helpers for team accents on Pickems surfaces.
enum ColorContrast {
    /// Minimum contrast for accent text/icons on the app background (WCAG AA normal text).
    static let minimumAccentContrast: Double = 4.5
    /// Minimum contrast for label text sitting on a solid accent fill.
    static let minimumOnAccentContrast: Double = 4.5

    struct RGB: Equatable {
        var r: Double
        var g: Double
        var b: Double

        var color: Color { Color(red: r, green: g, blue: b) }

        var hex: String {
            String(
                format: "#%02X%02X%02X",
                Int((r * 255).rounded()),
                Int((g * 255).rounded()),
                Int((b * 255).rounded())
            )
        }

        static func from(hex: String) -> RGB {
            var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitized = sanitized.replacingOccurrences(of: "#", with: "")
            var value: UInt64 = 0
            Scanner(string: sanitized).scanHexInt64(&value)
            return RGB(
                r: Double((value >> 16) & 0xFF) / 255,
                g: Double((value >> 8) & 0xFF) / 255,
                b: Double(value & 0xFF) / 255
            )
        }

        /// Relative luminance per WCAG 2.x.
        var luminance: Double {
            func channel(_ c: Double) -> Double {
                c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }

        func mixed(toward other: RGB, amount: Double) -> RGB {
            let t = min(max(amount, 0), 1)
            return RGB(
                r: r + (other.r - r) * t,
                g: g + (other.g - g) * t,
                b: b + (other.b - b) * t
            )
        }
    }

    static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let l1 = a.luminance
        let l2 = b.luminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Picks the candidate with the best contrast on `background`, lightening toward white if needed.
    /// Prefers chromatic team colors over pure white/black secondaries when both are readable.
    static func accessibleAccent(
        candidates: [RGB],
        against background: RGB,
        minimumRatio: Double = minimumAccentContrast
    ) -> RGB {
        let scored = candidates.map { (color: $0, ratio: contrastRatio($0, background)) }
        let passing = scored.filter { $0.ratio >= minimumRatio }
        let chromaticPassing = passing.filter { $0.color.luminance < 0.85 && $0.color.luminance > 0.08 }

        if let best = chromaticPassing.max(by: { $0.ratio < $1.ratio }) {
            return best.color
        }
        if let best = passing.max(by: { $0.ratio < $1.ratio }) {
            return best.color
        }

        // Dark team primaries (Auburn navy, Michigan blue, etc.) fail on near-black UIs.
        // Prefer lightening earlier candidates (primary first) to keep brand identity.
        for candidate in candidates {
            let adjusted = lightenedUntilReadable(candidate, against: background, minimumRatio: minimumRatio)
            if contrastRatio(adjusted, background) >= minimumRatio {
                return adjusted
            }
        }

        return lightenedUntilReadable(
            candidates.first ?? RGB(r: 0.86, g: 0.15, b: 0.15),
            against: background,
            minimumRatio: minimumRatio
        )
    }

    /// Darkens `color` toward black until it clears `minimumRatio` on a light surface.
    /// Channel ratios stay put, so Auburn orange stays orange instead of flipping to navy.
    static func darkenedUntilReadable(
        _ color: RGB,
        against background: RGB,
        minimumRatio: Double = minimumAccentContrast
    ) -> RGB {
        if contrastRatio(color, background) >= minimumRatio {
            return color
        }
        var best = color
        var low = 0.0
        var high = 1.0
        let black = RGB(r: 0, g: 0, b: 0)
        for _ in 0..<12 {
            let mid = (low + high) / 2
            let candidate = color.mixed(toward: black, amount: mid)
            if contrastRatio(candidate, background) >= minimumRatio {
                high = mid
                best = candidate
            } else {
                low = mid
            }
        }
        return best
    }

    static func uiColor(light: RGB, dark: RGB) -> UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        }
    }

    static func dynamicColor(light: RGB, dark: RGB) -> Color {
        Color(uiColor: uiColor(light: light, dark: dark))
    }

    private static func lightenedUntilReadable(
        _ color: RGB,
        against background: RGB,
        minimumRatio: Double
    ) -> RGB {
        if contrastRatio(color, background) >= minimumRatio {
            return color
        }
        var best = color
        var low = 0.0
        var high = 1.0
        for _ in 0..<12 {
            let mid = (low + high) / 2
            let candidate = color.mixed(toward: RGB(r: 1, g: 1, b: 1), amount: mid)
            if contrastRatio(candidate, background) >= minimumRatio {
                high = mid
                best = candidate
            } else {
                low = mid
            }
        }
        return best
    }

    /// White or near-black label color that contrasts with a solid accent fill.
    static func onAccent(for fill: RGB, minimumRatio: Double = minimumOnAccentContrast) -> RGB {
        let white = RGB(r: 1, g: 1, b: 1)
        let ink = RGB(r: 0.08, g: 0.08, b: 0.10)
        let whiteRatio = contrastRatio(white, fill)
        let inkRatio = contrastRatio(ink, fill)
        if whiteRatio >= minimumRatio || whiteRatio >= inkRatio {
            return white
        }
        return ink
    }

    /// Near-black canvas the dark UI has always used.
    static var appBackground: RGB {
        RGB(r: 0.08, g: 0.08, b: 0.10)
    }

    /// Cool off-white. Cards sit on top as pure white.
    static var lightAppBackground: RGB {
        RGB(r: 0.957, g: 0.961, b: 0.969)
    }
}

/// Semantic surfaces for both appearances. Dark values are the pre-light-mode palette.
/// Light status colors are the same hues darkened until they read on `lightAppBackground`.
struct PickemsSurfacePalette: Equatable {
    var background: ColorContrast.RGB
    var cardBackground: ColorContrast.RGB
    var textPrimary: ColorContrast.RGB
    var textSecondary: ColorContrast.RGB
    var success: ColorContrast.RGB
    var warning: ColorContrast.RGB
    var covering: ColorContrast.RGB
    var lost: ColorContrast.RGB
    var push: ColorContrast.RGB
    var accent: ColorContrast.RGB
    var accentSecondary: ColorContrast.RGB
    var progressGold: ColorContrast.RGB
}

enum PickemsSurfaces {
    static let dark = PickemsSurfacePalette(
        background: ColorContrast.appBackground,
        cardBackground: ColorContrast.RGB(r: 0.14, g: 0.14, b: 0.16),
        textPrimary: ColorContrast.RGB(r: 1, g: 1, b: 1),
        textSecondary: ColorContrast.RGB(r: 0.65, g: 0.65, b: 0.65),
        success: ColorContrast.RGB(r: 0.20, g: 0.78, b: 0.35),
        warning: ColorContrast.RGB(r: 0.95, g: 0.75, b: 0.20),
        covering: ColorContrast.RGB(r: 0.22, g: 0.48, b: 0.92),
        lost: ColorContrast.RGB(r: 0.86, g: 0.15, b: 0.15),
        push: ColorContrast.RGB(r: 0.36, g: 0.37, b: 0.40),
        accent: ColorContrast.RGB(r: 0.86, g: 0.15, b: 0.15),
        accentSecondary: ColorContrast.RGB(r: 0.65, g: 0.10, b: 0.10),
        progressGold: ColorContrast.RGB(r: 0.96, g: 0.76, b: 0.26)
    )

    static let light: PickemsSurfacePalette = {
        let background = ColorContrast.lightAppBackground
        func readable(_ color: ColorContrast.RGB) -> ColorContrast.RGB {
            ColorContrast.darkenedUntilReadable(color, against: background)
        }
        return PickemsSurfacePalette(
            background: background,
            cardBackground: ColorContrast.RGB(r: 1, g: 1, b: 1),
            textPrimary: ColorContrast.RGB(r: 0.08, g: 0.08, b: 0.10),
            textSecondary: ColorContrast.RGB(r: 0.29, g: 0.29, b: 0.32),
            success: readable(dark.success),
            warning: readable(dark.warning),
            covering: readable(dark.covering),
            lost: readable(dark.lost),
            push: readable(dark.push),
            accent: readable(dark.accent),
            accentSecondary: readable(dark.accentSecondary),
            progressGold: readable(dark.progressGold)
        )
    }()

    static func palette(for scheme: ColorScheme) -> PickemsSurfacePalette {
        scheme == .dark ? dark : light
    }
}

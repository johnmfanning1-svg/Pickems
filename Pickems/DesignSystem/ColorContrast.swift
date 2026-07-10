import Foundation
import SwiftUI

/// WCAG-oriented contrast helpers for team theming on Pickems' dark UI.
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

    static var appBackground: RGB {
        RGB(r: 0.08, g: 0.08, b: 0.10)
    }
}

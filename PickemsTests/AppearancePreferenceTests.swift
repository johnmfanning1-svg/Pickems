import Foundation
import SwiftUI
import Testing
@testable import Pickems

struct AppearancePreferenceTests {
    @Test func missingAndUnknownValuesStayDark() {
        #expect(AppearancePreference.resolve(stored: nil) == .dark)
        #expect(AppearancePreference.resolve(stored: "") == .dark)
        #expect(AppearancePreference.resolve(stored: "Light") == .dark)
        #expect(AppearancePreference.resolve(stored: "nope") == .dark)
        #expect(AppearancePreference.defaultPreference == .dark)
        #expect(AppearancePreference.defaultPreference.resolvedColorScheme == .dark)
    }

    @Test func systemLightAndDarkResolveTheColorScheme() {
        #expect(AppearancePreference.system.resolvedColorScheme == nil)
        #expect(AppearancePreference.light.resolvedColorScheme == .light)
        #expect(AppearancePreference.dark.resolvedColorScheme == .dark)
        #expect(AppearancePreference.resolve(stored: "system") == .system)
        #expect(AppearancePreference.resolve(stored: "light").resolvedColorScheme == .light)
        #expect(AppearancePreference.resolve(stored: "dark").resolvedColorScheme == .dark)
    }

    @Test func storeRoundTripsTheAppGroupKey() {
        let suite = "pickems.appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppearancePreference.storageKey == "appearance.preference")
        #expect(AppearancePreferenceStore.preference(defaults: defaults) == .dark)
        #expect(AppearancePreferenceStore.resolvedColorScheme(defaults: defaults) == .dark)
        #expect(defaults.object(forKey: AppearancePreference.storageKey) == nil)

        AppearancePreferenceStore.set(.light, defaults: defaults)
        #expect(defaults.string(forKey: AppearancePreference.storageKey) == "light")
        #expect(AppearancePreferenceStore.resolvedColorScheme(defaults: defaults) == .light)

        AppearancePreferenceStore.set(.system, defaults: defaults)
        #expect(AppearancePreferenceStore.preference(defaults: defaults) == .system)
        #expect(AppearancePreferenceStore.resolvedColorScheme(defaults: defaults) == nil)

        AppearancePreferenceStore.set(.dark, defaults: defaults)
        #expect(AppearancePreferenceStore.resolvedColorScheme(defaults: defaults) == .dark)
    }

    @Test func profileChoicesAreSystemLightDark() {
        #expect(AppearancePreference.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(AppearancePreference.allCases.map(\.label) == ["System", "Light", "Dark"])
    }

    @Test func semanticTextClearsContrastOnBothSurfaces() {
        for scheme in [ColorScheme.light, ColorScheme.dark] {
            let palette = PickemsSurfaces.palette(for: scheme)
            for background in [palette.background, palette.cardBackground] {
                #expect(ColorContrast.contrastRatio(palette.textPrimary, background) >= 4.5)
                #expect(ColorContrast.contrastRatio(palette.textSecondary, background) >= 4.5)
            }
        }
    }

    @Test func darkPaletteMatchesThePreLightModeColors() {
        let dark = PickemsSurfaces.dark
        #expect(dark.background == ColorContrast.appBackground)
        #expect(dark.background == ColorContrast.RGB(r: 0.08, g: 0.08, b: 0.10))
        #expect(dark.cardBackground == ColorContrast.RGB(r: 0.14, g: 0.14, b: 0.16))
        #expect(dark.textPrimary == ColorContrast.RGB(r: 1, g: 1, b: 1))
        #expect(dark.textSecondary == ColorContrast.RGB(r: 0.65, g: 0.65, b: 0.65))
        #expect(dark.success == ColorContrast.RGB(r: 0.20, g: 0.78, b: 0.35))
        #expect(dark.warning == ColorContrast.RGB(r: 0.95, g: 0.75, b: 0.20))
        #expect(dark.covering == ColorContrast.RGB(r: 0.22, g: 0.48, b: 0.92))
        #expect(dark.lost == ColorContrast.RGB(r: 0.86, g: 0.15, b: 0.15))
        #expect(dark.push == ColorContrast.RGB(r: 0.36, g: 0.37, b: 0.40))
        #expect(dark.accent == ColorContrast.RGB(r: 0.86, g: 0.15, b: 0.15))
        #expect(dark.progressGold == ColorContrast.RGB(r: 0.96, g: 0.76, b: 0.26))
        #expect(ColorContrast.lightAppBackground == ColorContrast.RGB(r: 0.957, g: 0.961, b: 0.969))
    }

    @Test func statusColorsReadOnTheirSurfaceAndKeepInk() {
        let lightBackground = PickemsSurfaces.light.background
        for key in statusKeys {
            let lightFill = PickemsSurfaces.light[keyPath: key]
            let darkFill = PickemsSurfaces.dark[keyPath: key]
            #expect(ColorContrast.contrastRatio(lightFill, lightBackground) >= 4.5)
            let lightInk = ColorContrast.onAccent(for: lightFill)
            #expect(ColorContrast.contrastRatio(lightInk, lightFill) >= 4.5)
        }

        let black = ColorContrast.RGB(r: 0, g: 0, b: 0)
        let white = ColorContrast.RGB(r: 1, g: 1, b: 1)
        #expect(ColorContrast.contrastRatio(black, PickemsSurfaces.dark.success) >= 4.5)
        #expect(ColorContrast.contrastRatio(black, PickemsSurfaces.dark.warning) >= 4.5)
        #expect(ColorContrast.contrastRatio(white, PickemsSurfaces.dark.lost) >= 4.5)
        #expect(ColorContrast.contrastRatio(white, PickemsSurfaces.dark.push) >= 4.5)
    }

    @Test func lightAccentDarkensTheDarkModeChoiceWithoutChangingHue() {
        let orange = ColorContrast.RGB.from(hex: "#E87722")
        let palette = TeamThemeCatalog.palette(for: "2")
        #expect(palette.accentDarkRGB == orange)
        #expect(palette.accentLightRGB == ColorContrast.darkenedUntilReadable(
            orange,
            against: ColorContrast.lightAppBackground
        ))
        #expect(ColorContrast.contrastRatio(palette.accentLightRGB, ColorContrast.lightAppBackground) >= 4.5)
        #expect(ColorContrast.contrastRatio(
            ColorContrast.onAccent(for: palette.accentLightRGB),
            palette.accentLightRGB
        ) >= 4.5)
        #expect(sameHue(palette.accentLightRGB, orange))
        #expect(palette.accentLightRGB.r > palette.accentLightRGB.b)

        let lightBackground = ColorContrast.lightAppBackground
        let darkBackground = ColorContrast.appBackground
        for team in TeamThemeCatalog.sortedTeams {
            let primary = ColorContrast.RGB.from(hex: team.primaryHex)
            let secondary = ColorContrast.RGB.from(hex: team.secondaryHex)
            let darkAccent = ColorContrast.accessibleAccent(
                candidates: [primary, secondary],
                against: darkBackground
            )
            let lightAccent = ColorContrast.darkenedUntilReadable(darkAccent, against: lightBackground)
            #expect(lightAccent.r <= darkAccent.r + 0.000_001)
            #expect(lightAccent.g <= darkAccent.g + 0.000_001)
            #expect(lightAccent.b <= darkAccent.b + 0.000_001)
            #expect(sameHue(lightAccent, darkAccent))
            #expect(ColorContrast.contrastRatio(lightAccent, lightBackground) >= 4.5)
            #expect(ColorContrast.contrastRatio(ColorContrast.onAccent(for: lightAccent), lightAccent) >= 4.5)
        }
    }

    @Test func widgetCopiesMatchTheAppSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pairs = [
            ("Pickems/DesignSystem/AppearancePreference.swift", "PickemsWidget/AppearancePreference.swift"),
            ("Pickems/DesignSystem/ColorContrast.swift", "PickemsWidget/ColorContrast.swift"),
        ]
        for (app, widget) in pairs {
            let left = try String(contentsOf: root.appendingPathComponent(app), encoding: .utf8)
            let right = try String(contentsOf: root.appendingPathComponent(widget), encoding: .utf8)
            #expect(left == right)
        }
    }

    private var statusKeys: [KeyPath<PickemsSurfacePalette, ColorContrast.RGB>] {
        [\.success, \.warning, \.covering, \.lost, \.push]
    }

    private func sameHue(_ adapted: ColorContrast.RGB, _ original: ColorContrast.RGB) -> Bool {
        func parts(_ color: ColorContrast.RGB) -> (Double, Double, Double) {
            let sum = color.r + color.g + color.b
            guard sum > 0 else { return (0, 0, 0) }
            return (color.r / sum, color.g / sum, color.b / sum)
        }
        let left = parts(adapted)
        let right = parts(original)
        return abs(left.0 - right.0) < 0.02
            && abs(left.1 - right.1) < 0.02
            && abs(left.2 - right.2) < 0.02
    }
}

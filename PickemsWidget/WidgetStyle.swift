import SwiftUI
import WidgetKit

/// Typography and spacing for every widget family. Sizes live here so layouts do not pick their own.
private struct WidgetFamilyOverrideKey: EnvironmentKey {
    static let defaultValue: WidgetFamily? = nil
}

private struct WidgetBackgroundOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Previews set these because `widgetFamily` and `showsWidgetContainerBackground` are read-only.
    var widgetFamilyOverride: WidgetFamily? {
        get { self[WidgetFamilyOverrideKey.self] }
        set { self[WidgetFamilyOverrideKey.self] = newValue }
    }

    var showsWidgetBackgroundOverride: Bool? {
        get { self[WidgetBackgroundOverrideKey.self] }
        set { self[WidgetBackgroundOverrideKey.self] = newValue }
    }
}

enum WidgetStyle {
    static let rowSpacing: CGFloat = 6
    static let neutralBar = Color(white: 0.45)

    static func canvas(_ scheme: ColorScheme) -> Color {
        surface(\.background, scheme)
    }

    static func brandRed(_ scheme: ColorScheme) -> Color {
        surface(\.accent, scheme)
    }

    static func winGreen(_ scheme: ColorScheme) -> Color {
        surface(\.success, scheme)
    }

    static func progressGold(_ scheme: ColorScheme) -> Color {
        surface(\.progressGold, scheme)
    }

    private static func surface(
        _ key: KeyPath<PickemsSurfacePalette, ColorContrast.RGB>,
        _ scheme: ColorScheme
    ) -> Color {
        PickemsSurfaces.palette(for: scheme)[keyPath: key].color
    }

    static func padding(for family: WidgetFamily) -> CGFloat {
        family == .systemSmall ? 14 : 16
    }

    static func usesHomePadding(_ family: WidgetFamily) -> Bool {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
            return true
        default:
            return false
        }
    }

    /// StandBy and lock-screen clear backgrounds drop the platter, so the hero grows.
    static func heroPointSize(for family: WidgetFamily, enlarged: Bool) -> CGFloat {
        let base: CGFloat
        switch family {
        case .systemSmall:
            base = 40
        case .systemMedium, .systemLarge, .systemExtraLarge:
            base = 34
        default:
            base = 22
        }
        return enlarged ? base + 8 : base
    }

    static func heroFont(for family: WidgetFamily, enlarged: Bool) -> Font {
        .system(size: heroPointSize(for: family, enlarged: enlarged), weight: .bold, design: .rounded)
    }

    static var titleFont: Font { .subheadline.weight(.bold) }
    static var rowFont: Font { .footnote.monospacedDigit() }
    static var eyebrowFont: Font { .caption2.weight(.semibold) }

    /// Full color keeps the brand hue. Accented and vibrant fall back to the system tint.
    static func accented(_ color: Color, mode: WidgetRenderingMode) -> Color {
        mode == .fullColor ? color : .primary
    }

    static func color(hex: String?, mode: WidgetRenderingMode) -> Color {
        guard mode == .fullColor, let hex else { return mode == .fullColor ? neutralBar : .primary }
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return neutralBar
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }
}

struct WidgetEyebrow: View {
    var text: String

    var body: some View {
        Text(text)
            .font(WidgetStyle.eyebrowFont)
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct WidgetUpdatedLine: View {
    var date: Date

    var body: some View {
        HStack(spacing: 4) {
            Text("Updated")
                .font(WidgetStyle.eyebrowFont)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(date, style: .relative)
                .font(WidgetStyle.eyebrowFont)
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

struct WidgetRefreshButton: View {
    var body: some View {
        Button(intent: RefreshWidgetIntent()) {
            Text("Tap to refresh")
                .font(WidgetStyle.rowFont)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct HomeWidgetBackground: ViewModifier {
    var family: WidgetFamily

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var systemShowsBackground
    @Environment(\.showsWidgetBackgroundOverride) private var showsBackgroundOverride
    @Environment(\.colorScheme) private var colorScheme

    private var showsBackground: Bool { showsBackgroundOverride ?? systemShowsBackground }

    func body(content: Content) -> some View {
        let pad = WidgetStyle.usesHomePadding(family)
            ? (showsBackground ? WidgetStyle.padding(for: family) : 8)
            : 0
        content
            .padding(pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .containerBackground(for: .widget) {
                if !showsBackground || renderingMode != .fullColor {
                    Color.clear
                } else {
                    WidgetStyle.canvas(colorScheme)
                }
            }
    }
}

struct AccessoryBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
    }
}

struct YouRowChrome: ViewModifier {
    var isYou: Bool

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, isYou ? 6 : 0)
            .padding(.vertical, isYou ? 2 : 0)
            .background {
                if isYou {
                    Capsule()
                        .fill(WidgetStyle.accented(WidgetStyle.brandRed(colorScheme), mode: renderingMode).opacity(renderingMode == .fullColor ? 0.22 : 0.18))
                        .widgetAccentable()
                }
            }
    }
}

extension View {
    @ViewBuilder
    func widgetLink(_ url: URL?) -> some View {
        if let url {
            Link(destination: url) { self }
        } else {
            self
        }
    }
}

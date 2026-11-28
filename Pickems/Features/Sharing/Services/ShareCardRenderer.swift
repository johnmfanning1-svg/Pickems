import SwiftUI
import UIKit

@MainActor
enum ShareCardRenderer {
    static func renderImage(
        for result: ShareableResult,
        palette: ThemePalette,
        size: CGSize = CGSize(width: 1200, height: 630)
    ) -> UIImage? {
        let scheme = renderingScheme
        let card = ResultsShareCard(result: result, palette: palette)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)

        return render(
            card,
            proposedSize: ProposedViewSize(size),
            scale: 2,
            colorScheme: scheme
        )
    }

    static func renderScreenCard(_ content: ScreenShareContent) -> UIImage? {
        let scheme = renderingScheme
        let card = screenCard(for: content)
            .frame(minWidth: ShareCardLayout.renderWidth, maxWidth: ShareCardLayout.renderWidth, alignment: .topLeading)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)

        return render(
            card,
            proposedSize: ProposedViewSize(width: ShareCardLayout.renderWidth, height: nil),
            scale: 3,
            colorScheme: scheme
        )
    }

    @ViewBuilder
    private static func screenCard(for content: ScreenShareContent) -> some View {
        switch content {
        case .leaderboard(let model):
            LeaderboardShareCard(model: model)
        case .seasonLedger(let model):
            SeasonLedgerShareCard(model: model)
        case .pickemsChart(let model):
            LeaguePickemsShareCard(model: model)
        }
    }

    static func render<V: View>(
        _ content: V,
        proposedSize: ProposedViewSize,
        scale: CGFloat,
        colorScheme: ColorScheme? = nil
    ) -> UIImage? {
        let scheme = colorScheme ?? renderingScheme
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = proposedSize
        renderer.scale = scale
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        var image: UIImage?
        traits.performAsCurrent {
            image = renderer.uiImage
        }
        return image
    }

    /// Share images are drawn offscreen, so they take the saved appearance instead of a default light trait.
    static var renderingScheme: ColorScheme {
        if let scheme = AppearancePreferenceStore.resolvedColorScheme() {
            return scheme
        }
        return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }
}

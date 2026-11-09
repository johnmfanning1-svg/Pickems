import SwiftUI
import UIKit

@MainActor
enum ShareCardRenderer {
    static func renderImage(
        for result: ShareableResult,
        palette: ThemePalette,
        size: CGSize = CGSize(width: 1200, height: 630)
    ) -> UIImage? {
        let scheme = ShareCardRenderer.renderingScheme
        let card = ResultsShareCard(result: result, palette: palette)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        var image: UIImage?
        traits.performAsCurrent {
            image = renderer.uiImage
        }
        return image
    }

    /// Share images are drawn offscreen, so they take the saved appearance instead of a default light trait.
    private static var renderingScheme: ColorScheme {
        if let scheme = AppearancePreferenceStore.resolvedColorScheme() {
            return scheme
        }
        return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }
}

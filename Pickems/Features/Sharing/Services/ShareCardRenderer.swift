import SwiftUI

@MainActor
enum ShareCardRenderer {
    static func renderImage(
        for result: ShareableResult,
        palette: ThemePalette,
        size: CGSize = CGSize(width: 1200, height: 630)
    ) -> UIImage? {
        let card = ResultsShareCard(result: result, palette: palette)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        return renderer.uiImage
    }
}

import SwiftUI

@MainActor
enum ShareCardRenderer {
    static func renderImage(for result: ShareableResult, size: CGSize = CGSize(width: 1200, height: 630)) -> UIImage? {
        let card = ResultsShareCard(result: result)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        return renderer.uiImage
    }
}

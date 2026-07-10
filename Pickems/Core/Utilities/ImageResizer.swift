import UIKit

enum ImageResizer {
    /// Downscales large camera/library photos before upload to avoid memory pressure crashes.
    static func resizedJPEGData(
        from image: UIImage,
        maxDimension: CGFloat = 1024,
        quality: CGFloat = 0.75
    ) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let maxSide = max(pixelWidth, pixelHeight)
        guard maxSide > 0 else { return nil }

        let scale = min(1, maxDimension / maxSide)
        let targetSize = CGSize(
            width: floor(pixelWidth * scale),
            height: floor(pixelHeight * scale)
        )
        guard targetSize.width > 0, targetSize.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

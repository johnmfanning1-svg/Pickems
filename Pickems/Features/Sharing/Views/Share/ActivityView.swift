import LinkPresentation
import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Image-first share payload so iMessage/Instagram get the card, not a website preview.
final class ResultsSharePayload: NSObject, UIActivityItemSource {
    let result: ShareableResult
    let image: UIImage?

    init(result: ShareableResult, image: UIImage?) {
        self.result = result
        self.image = image
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image ?? result.messageText
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        if activityType == .copyToPasteboard {
            return result.messageText
        }
        if activityType == .postToTwitter {
            return result.tweetText
        }
        return image ?? result.messageText
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = result.headline
        if let image {
            metadata.imageProvider = NSItemProvider(object: image)
            metadata.iconProvider = NSItemProvider(object: image)
        }
        return metadata
    }
}

/// Image-first share for league screen cards (leaderboard, ledger, Pickems chart).
final class ScreenSharePayload: NSObject, UIActivityItemSource {
    let title: String
    let caption: String
    let image: UIImage?

    init(title: String, caption: String, image: UIImage?) {
        self.title = title
        self.caption = caption
        self.image = image
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image ?? caption
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        if activityType == .copyToPasteboard {
            return caption
        }
        return image ?? caption
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        if let image {
            metadata.imageProvider = NSItemProvider(object: image)
            metadata.iconProvider = NSItemProvider(object: image)
        }
        return metadata
    }
}

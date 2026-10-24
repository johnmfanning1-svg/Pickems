import Foundation
import Testing
import UIKit
@testable import Pickems

@MainActor
struct AnchoredInfoPopoverTests {
    @Test func popoverAnchorsToSourceAndAllowsFlip() throws {
        let source = AnchoredInfoPopoverAnchorView(
            frame: CGRect(x: 200, y: 320, width: 44, height: 44)
        )
        source.message = SpreadLineCopy.infoMessage(
            locked: "LSU -7.5",
            live: "LSU -7.0",
            isFinal: false
        ) ?? "fallback"
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        container.addSubview(header)
        container.addSubview(source)

        let content = source.makeContentController()
        let popover = try #require(content.popoverPresentationController)

        #expect(content.modalPresentationStyle == .popover)
        #expect(popover.sourceView.map(ObjectIdentifier.init) == ObjectIdentifier(source))
        #expect(popover.sourceRect == source.bounds)
        #expect(popover.sourceRect == CGRect(x: 0, y: 0, width: 44, height: 44))
        #expect(popover.sourceView.map(ObjectIdentifier.init) != ObjectIdentifier(header))
        #expect(popover.sourceView.map(ObjectIdentifier.init) != ObjectIdentifier(container))
        #expect(popover.permittedArrowDirections.contains(.up))
        #expect(popover.permittedArrowDirections.contains(.down))

        let presentation = UIPresentationController(
            presentedViewController: UIViewController(),
            presenting: UIViewController()
        )
        let adapted = popover.delegate?.adaptivePresentationStyle?(
            for: presentation,
            traitCollection: UITraitCollection(horizontalSizeClass: .compact)
        )
        #expect(adapted == UIModalPresentationStyle.none)
    }

    @Test func fittingContentSizeShowsFullMessageNotASingleLine() throws {
        let message = try #require(
            SpreadLineCopy.infoMessage(locked: "LSU -7.5", live: "LSU -7.0", isFinal: false)
        )
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let singleLine = (message as NSString).size(withAttributes: [.font: font]).height
        let fitted = AnchoredInfoPopoverController.fittingContentSize(
            message: message,
            maxWidth: 290,
            maxHeight: 400,
            font: font
        )

        #expect(fitted.width == 290)
        // Multi-line bubble: taller than one line of text plus vertical padding alone would imply
        // if the popover wrongly sized to a single truncated line.
        #expect(fitted.height > singleLine + AnchoredInfoPopoverController.verticalPadding)
        #expect(fitted.height >= 48)

        // Cap forces a shorter frame than the natural text height so the bubble can scroll
        // at large Dynamic Type instead of overflowing the safe area.
        let capped = AnchoredInfoPopoverController.fittingContentSize(
            message: message,
            maxWidth: 290,
            maxHeight: 40,
            font: font
        )
        let uncapped = AnchoredInfoPopoverController.fittingContentSize(
            message: message,
            maxWidth: 290,
            maxHeight: .greatestFiniteMagnitude,
            font: font
        )
        #expect(capped.height == 40)
        #expect(uncapped.height > capped.height)
    }
}

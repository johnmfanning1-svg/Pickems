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

    @Test func presenterWalkReturnsOpenInfoBubbleAsTop() {
        let root = StubPresenter()
        let openBubble = AnchoredInfoPopoverController(message: "already open")
        root.fakePresented = openBubble

        let top = AnchoredInfoPopover.topPresenter(startingAt: root)
        #expect(top.map(ObjectIdentifier.init) == ObjectIdentifier(openBubble))
        #expect(top is AnchoredInfoPopoverController)
    }

    @Test func presentSkipsWhenTopIsAlreadyInfoPopover() {
        let openBubble = AnchoredInfoPopoverController(message: "already open")
        let anchor = AnchoredInfoPopoverAnchorView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        anchor.message = "second"
        var didPresent = false
        anchor.resolvePresenter = { openBubble }
        anchor.presentContent = { _, _ in didPresent = true }

        anchor.present(animated: false)

        #expect(!didPresent)
        #expect(anchor.presentedController == nil)
    }

    @Test func presentProceedsWhenPresenterHasNothingPresented() {
        let root = StubPresenter()
        let anchor = AnchoredInfoPopoverAnchorView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        anchor.message = "fresh"
        var presented: AnchoredInfoPopoverController?
        anchor.resolvePresenter = { root }
        anchor.presentContent = { content, _ in presented = content }

        anchor.present(animated: false)

        #expect(presented?.message == "fresh")
        #expect(anchor.presentedController.map(ObjectIdentifier.init) == presented.map(ObjectIdentifier.init))
    }

    @Test func dismissPresentedPopoverClearsHandleAndInvokesDismissSeam() {
        let anchor = AnchoredInfoPopoverAnchorView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        let content = AnchoredInfoPopoverController(message: "manual dismiss")
        var focusRestoreCount = 0
        anchor.onDismissed = { focusRestoreCount += 1 }
        anchor.attachPresentedForTesting(content)

        var dismissed: AnchoredInfoPopoverController?
        var completionRan = false
        anchor.dismissHandler = { controller, _, completion in
            dismissed = controller
            completion?()
        }

        anchor.dismissPresentedPopover(animated: false) {
            completionRan = true
        }

        #expect(dismissed.map(ObjectIdentifier.init) == ObjectIdentifier(content))
        #expect(anchor.presentedController == nil)
        #expect(content.onDismissed == nil)
        #expect(completionRan)
        // Hierarchy-style clear of onDismissed must not bounce VoiceOver focus.
        #expect(focusRestoreCount == 0)
    }

    @Test func willMoveToNilWindowDismissesViaSeam() {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let anchor = AnchoredInfoPopoverAnchorView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        parent.addSubview(anchor)

        let content = AnchoredInfoPopoverController(message: "leaves hierarchy")
        anchor.attachPresentedForTesting(content)

        var dismissed: AnchoredInfoPopoverController?
        anchor.dismissHandler = { controller, _, completion in
            dismissed = controller
            completion?()
        }

        // Mirrors List recycle / removeFromSuperview without a real UIWindow.
        anchor.willMove(toWindow: nil)

        #expect(dismissed.map(ObjectIdentifier.init) == ObjectIdentifier(content))
        #expect(anchor.presentedController == nil)
        #expect(content.onDismissed == nil)
    }

    @Test func dismantleUIViewDismissesViaSeam() {
        let anchor = AnchoredInfoPopoverAnchorView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        let content = AnchoredInfoPopoverController(message: "dismantle")
        anchor.attachPresentedForTesting(content)

        var dismissed: AnchoredInfoPopoverController?
        anchor.dismissHandler = { controller, _, completion in
            dismissed = controller
            completion?()
        }

        AnchoredInfoPopoverAnchor.dismantleUIView(anchor, coordinator: ())

        #expect(dismissed.map(ObjectIdentifier.init) == ObjectIdentifier(content))
        #expect(anchor.presentedController == nil)
        #expect(anchor.onDismissed == nil)
    }

    @Test func notifyDismissedInvokesCallbackOnce() {
        let content = AnchoredInfoPopoverController(message: "focus return")
        var count = 0
        content.onDismissed = { count += 1 }

        content.notifyDismissedIfNeeded()
        content.notifyDismissedIfNeeded()

        #expect(count == 1)
        #expect(content.didNotifyDismissed)
        #expect(content.onDismissed == nil)
    }

    @Test func notifyDismissedSkipsWhenCallbackAlreadyCleared() {
        let content = AnchoredInfoPopoverController(message: "hierarchy dismiss")
        var count = 0
        content.onDismissed = { count += 1 }
        // Same order as dismissPresentedPopover: clear before teardown notify.
        content.onDismissed = nil

        content.notifyDismissedIfNeeded()

        #expect(count == 0)
        #expect(content.didNotifyDismissed)
    }
}

/// In-memory presented-VC stand-in so presenter-walk tests need no key window.
@MainActor
private final class StubPresenter: UIViewController {
    var fakePresented: UIViewController?
    override var presentedViewController: UIViewController? { fakePresented }
}

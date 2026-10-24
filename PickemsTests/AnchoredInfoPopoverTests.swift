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

    @Test func presentUsesRootPresenterAndDoesNotStackSecondBubble() async throws {
        let harness = try AnchoredInfoPopoverWindowHarness()
        defer { harness.tearDown() }

        let first = harness.installAnchor(
            frame: CGRect(x: 40, y: 120, width: 44, height: 44),
            message: "First bubble"
        )
        let second = harness.installAnchor(
            frame: CGRect(x: 40, y: 200, width: 44, height: 44),
            message: "Second bubble"
        )

        first.present(animated: false)
        try await waitUntil {
            harness.host.presentedViewController is AnchoredInfoPopoverController
        }

        let presented = try #require(harness.host.presentedViewController as? AnchoredInfoPopoverController)
        #expect(presented.message == "First bubble")
        #expect(presented.popoverPresentationController?.sourceView.map(ObjectIdentifier.init) == ObjectIdentifier(first))

        // Presenter walk lands on the open bubble; re-present must skip, not stack.
        second.present(animated: false)
        first.present(animated: false)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(harness.host.presentedViewController.map(ObjectIdentifier.init) == ObjectIdentifier(presented))
        #expect(presented.presentedViewController == nil)
        #expect(!(harness.host.presentedViewController?.presentedViewController is AnchoredInfoPopoverController))
    }

    @Test func dismissesWhenAnchorLeavesWindow() async throws {
        let harness = try AnchoredInfoPopoverWindowHarness()
        defer { harness.tearDown() }

        let anchor = harness.installAnchor(
            frame: CGRect(x: 40, y: 120, width: 44, height: 44),
            message: "Leaves window"
        )
        anchor.present(animated: false)
        try await waitUntil {
            harness.host.presentedViewController is AnchoredInfoPopoverController
        }
        #expect(harness.host.presentedViewController is AnchoredInfoPopoverController)

        anchor.removeFromSuperview()
        try await waitUntil {
            harness.host.presentedViewController == nil
        }
        #expect(harness.host.presentedViewController == nil)
    }

    @Test func dismissPresentedPopoverClearsBubbleWithoutStacking() async throws {
        let harness = try AnchoredInfoPopoverWindowHarness()
        defer { harness.tearDown() }

        let anchor = harness.installAnchor(
            frame: CGRect(x: 40, y: 120, width: 44, height: 44),
            message: "Manual dismiss"
        )
        anchor.present(animated: false)
        try await waitUntil {
            harness.host.presentedViewController is AnchoredInfoPopoverController
        }

        anchor.dismissPresentedPopover(animated: false)
        try await waitUntil {
            harness.host.presentedViewController == nil
        }
        #expect(harness.host.presentedViewController == nil)

        // After clearing, a fresh present works again.
        anchor.present(animated: false)
        try await waitUntil {
            harness.host.presentedViewController is AnchoredInfoPopoverController
        }
        let again = try #require(harness.host.presentedViewController as? AnchoredInfoPopoverController)
        #expect(again.message == "Manual dismiss")
    }

    @Test func interactiveDismissNotifiesOnDismissed() async throws {
        let harness = try AnchoredInfoPopoverWindowHarness()
        defer { harness.tearDown() }

        var dismissCount = 0
        let anchor = harness.installAnchor(
            frame: CGRect(x: 40, y: 120, width: 44, height: 44),
            message: "Focus return"
        )
        anchor.onDismissed = { dismissCount += 1 }

        anchor.present(animated: false)
        try await waitUntil {
            harness.host.presentedViewController is AnchoredInfoPopoverController
        }
        let presented = try #require(harness.host.presentedViewController as? AnchoredInfoPopoverController)

        // Simulate tap-outside / programmatic dismiss (viewDidDisappear → onDismissed).
        presented.dismiss(animated: false)
        try await waitUntil { dismissCount == 1 }
        try await waitUntil { harness.host.presentedViewController == nil }

        #expect(dismissCount == 1)
        #expect(harness.host.presentedViewController == nil)
    }

    @Test func dismantleUIViewDismissesPresentedBubble() async throws {
        let harness = try AnchoredInfoPopoverWindowHarness()
        defer { harness.tearDown() }

        let anchor = harness.installAnchor(
            frame: CGRect(x: 40, y: 120, width: 44, height: 44),
            message: "Dismantle"
        )
        anchor.present(animated: false)
        try await waitUntil {
            harness.host.presentedViewController is AnchoredInfoPopoverController
        }

        AnchoredInfoPopoverAnchor.dismantleUIView(anchor, coordinator: ())
        try await waitUntil {
            harness.host.presentedViewController == nil
        }
        #expect(harness.host.presentedViewController == nil)
    }
}

// MARK: - Test helpers

@MainActor
private final class AnchoredInfoPopoverWindowHarness {
    let window: UIWindow
    let host: UIViewController
    private let previousKey: UIWindow?

    init() throws {
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        previousKey = scene?.windows.first { $0.isKeyWindow }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        self.window = window
        self.host = host
    }

    func installAnchor(frame: CGRect, message: String) -> AnchoredInfoPopoverAnchorView {
        let anchor = AnchoredInfoPopoverAnchorView(frame: frame)
        anchor.message = message
        host.view.addSubview(anchor)
        return anchor
    }

    func tearDown() {
        host.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        if let previousKey, previousKey !== window {
            previousKey.makeKeyAndVisible()
        }
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollNanoseconds: UInt64 = 20_000_000,
    _ condition: () -> Bool
) async throws {
    let deadline = DispatchTime.now() + .nanoseconds(Int(timeoutNanoseconds))
    while DispatchTime.now() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
    #expect(condition(), "Condition not met before timeout")
}

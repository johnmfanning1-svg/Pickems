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

/// Window-hierarchy coverage for `present()`, the presenter-walk re-present guard, and dismissal.
/// Serialized so parallel MainActor tests do not fight over the key window.
@Suite(.serialized)
@MainActor
struct AnchoredInfoPopoverPresentationTests {
    @Test func presentUsesRootPresenterAndDoesNotStackSecondBubble() async throws {
        try await withPopoverHarness { harness in
            let first = harness.installAnchor(
                frame: CGRect(x: 40, y: 120, width: 44, height: 44),
                message: "First bubble"
            )
            let second = harness.installAnchor(
                frame: CGRect(x: 40, y: 200, width: 44, height: 44),
                message: "Second bubble"
            )

            first.present(animated: false)
            let presented = try await harness.requirePresentedPopover()
            #expect(presented.message == "First bubble")
            #expect(
                presented.popoverPresentationController?.sourceView.map(ObjectIdentifier.init)
                    == ObjectIdentifier(first)
            )

            // Presenter walk lands on the open bubble; re-present must skip, not stack.
            second.present(animated: false)
            first.present(animated: false)
            try await Task.sleep(nanoseconds: 100_000_000)

            #expect(harness.host.presentedViewController.map(ObjectIdentifier.init) == ObjectIdentifier(presented))
            #expect(presented.presentedViewController == nil)
            #expect(!(harness.host.presentedViewController?.presentedViewController is AnchoredInfoPopoverController))
        }
    }

    @Test func dismissesWhenAnchorLeavesWindow() async throws {
        try await withPopoverHarness { harness in
            let anchor = harness.installAnchor(
                frame: CGRect(x: 40, y: 120, width: 44, height: 44),
                message: "Leaves window"
            )
            anchor.present(animated: false)
            _ = try await harness.requirePresentedPopover()

            anchor.removeFromSuperview()
            try await harness.waitUntilDismissed()
            #expect(harness.host.presentedViewController == nil)
        }
    }

    @Test func dismissPresentedPopoverClearsBubbleWithoutStacking() async throws {
        try await withPopoverHarness { harness in
            let anchor = harness.installAnchor(
                frame: CGRect(x: 40, y: 120, width: 44, height: 44),
                message: "Manual dismiss"
            )
            anchor.present(animated: false)
            _ = try await harness.requirePresentedPopover()

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                anchor.dismissPresentedPopover(animated: false) {
                    cont.resume()
                }
            }
            try await harness.waitUntilDismissed()
            #expect(harness.host.presentedViewController == nil)

            // After clearing, a fresh present works again.
            anchor.present(animated: false)
            let again = try await harness.requirePresentedPopover()
            #expect(again.message == "Manual dismiss")
        }
    }

    @Test func interactiveDismissNotifiesOnDismissed() async throws {
        try await withPopoverHarness { harness in
            var dismissCount = 0
            let anchor = harness.installAnchor(
                frame: CGRect(x: 40, y: 120, width: 44, height: 44),
                message: "Focus return"
            )
            anchor.onDismissed = { dismissCount += 1 }

            anchor.present(animated: false)
            let presented = try await harness.requirePresentedPopover()

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                presented.dismiss(animated: false) {
                    cont.resume()
                }
            }
            try await waitUntil { dismissCount == 1 }
            try await harness.waitUntilDismissed()

            #expect(dismissCount == 1)
            #expect(harness.host.presentedViewController == nil)
        }
    }

    @Test func dismantleUIViewDismissesPresentedBubble() async throws {
        try await withPopoverHarness { harness in
            let anchor = harness.installAnchor(
                frame: CGRect(x: 40, y: 120, width: 44, height: 44),
                message: "Dismantle"
            )
            anchor.present(animated: false)
            _ = try await harness.requirePresentedPopover()

            AnchoredInfoPopoverAnchor.dismantleUIView(anchor, coordinator: ())
            try await harness.waitUntilDismissed()
            #expect(harness.host.presentedViewController == nil)
        }
    }
}

// MARK: - Test helpers

@MainActor
private func withPopoverHarness(
    _ body: (AnchoredInfoPopoverWindowHarness) async throws -> Void
) async throws {
    let harness = try await AnchoredInfoPopoverWindowHarness.make()
    do {
        try await body(harness)
        await harness.tearDown()
    } catch {
        await harness.tearDown()
        throw error
    }
}

@MainActor
private final class AnchoredInfoPopoverWindowHarness {
    let window: UIWindow
    let host: UIViewController
    private let previousKey: UIWindow?

    static func make() async throws -> AnchoredInfoPopoverWindowHarness {
        let harness = AnchoredInfoPopoverWindowHarness()
        // Let the window become key before presenting popovers.
        try await Task.sleep(nanoseconds: 50_000_000)
        return harness
    }

    private init() {
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

    func requirePresentedPopover() async throws -> AnchoredInfoPopoverController {
        try await waitUntil {
            host.presentedViewController is AnchoredInfoPopoverController
        }
        return try #require(host.presentedViewController as? AnchoredInfoPopoverController)
    }

    func waitUntilDismissed() async throws {
        try await waitUntil { host.presentedViewController == nil }
    }

    func tearDown() async {
        if host.presentedViewController != nil {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                host.dismiss(animated: false) {
                    cont.resume()
                }
            }
        }
        window.isHidden = true
        window.rootViewController = nil
        if let previousKey, previousKey !== window {
            previousKey.makeKeyAndVisible()
        }
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    pollNanoseconds: UInt64 = 20_000_000,
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = DispatchTime.now() + .nanoseconds(Int(timeoutNanoseconds))
    while DispatchTime.now() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
    #expect(condition(), "Condition not met before timeout")
}

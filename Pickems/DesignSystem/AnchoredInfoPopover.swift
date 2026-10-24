import SwiftUI
import UIKit

/// Fires presentation from a SwiftUI control into its matching UIKit anchor view.
@MainActor
final class AnchoredInfoPopoverTrigger {
    var fireImpl: (() -> Void)?
    /// Called after the popover finishes dismissing so VoiceOver can return to the (i) button.
    var onDismissed: (() -> Void)?

    func fire() {
        fireImpl?()
    }
}

/// Text info bubble presented as a true UIKit popover.
///
/// Escapes clipped cards / list rows / ScrollViews, anchors to the tapped control,
/// and flips above or below when space is tight (`permittedArrowDirections` up+down).
final class AnchoredInfoPopoverAnchorView: UIView {
    var message = ""
    var maxWidth: CGFloat = 290
    var onDismissed: (() -> Void)?

    /// Weak handle so we can dismiss when this anchor leaves the window or is dismantled.
    private weak var presentedController: AnchoredInfoPopoverController?

    func makeContentController() -> AnchoredInfoPopoverController {
        let controller = AnchoredInfoPopoverController(message: message, maxWidth: maxWidth)
        AnchoredInfoPopover.anchor(controller, to: self)
        return controller
    }

    func present(animated: Bool = true) {
        guard window != nil else { return }
        guard let presenter = pickemsTopPresenter() else { return }
        // The presenter walk would otherwise treat an open info bubble as `top`, whose
        // `presentedViewController` is nil — stacking a second bubble on the first.
        if presenter is AnchoredInfoPopoverController {
            return
        }
        guard presenter.presentedViewController == nil else { return }

        let content = makeContentController()
        content.onDismissed = { [weak self] in
            self?.handlePopoverDismissed()
        }
        presentedController = content
        presenter.present(content, animated: animated)
    }

    /// Dismisses any bubble this anchor presented (row recycle / dismantle / leave window).
    func dismissPresentedPopover(animated: Bool = false) {
        guard let presented = presentedController,
              presented.presentingViewController != nil else {
            presentedController = nil
            return
        }
        // Leaving the hierarchy — do not bounce VoiceOver onto a recycled/gone control.
        presented.onDismissed = nil
        presented.dismiss(animated: animated)
        presentedController = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            dismissPresentedPopover(animated: false)
        }
    }

    private func handlePopoverDismissed() {
        presentedController = nil
        onDismissed?()
    }
}

enum AnchoredInfoPopover {
    /// Popover source is `source` (the tapped control), in that view's own coordinates.
    static func anchor(_ controller: UIViewController, to source: UIView) {
        controller.modalPresentationStyle = .popover
        let delegate = AnchoredInfoPopoverDelegate()
        objc_setAssociatedObject(
            controller,
            &AnchoredInfoPopoverRetain.key,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceView = source
        popover.sourceRect = source.bounds
        popover.permittedArrowDirections = [.up, .down]
        popover.delegate = delegate
    }
}

/// Scrollable, Dynamic-Type-aware message sized to its content (capped for tall accessibility sizes).
final class AnchoredInfoPopoverController: UIViewController {
    static let defaultMaxWidth: CGFloat = 290
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12

    let message: String
    let maxWidth: CGFloat
    /// Invoked once when this popover finishes dismissing (tap outside, swipe, etc.).
    var onDismissed: (() -> Void)?

    private let scrollView = UIScrollView()
    private let label = UILabel()
    private var didNotifyDismissed = false

    init(message: String, maxWidth: CGFloat = defaultMaxWidth) {
        self.message = message
        self.maxWidth = maxWidth
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        // Size before presentation so the popover frame matches the full message.
        preferredContentSize = Self.fittingContentSize(
            message: message,
            maxWidth: maxWidth,
            maxHeight: Self.defaultMaxHeight()
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(PickemsColors.cardBackground)

        label.text = message
        label.numberOfLines = 0
        label.textColor = UIColor(PickemsColors.textPrimary)
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byWordWrapping

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never

        view.addSubview(scrollView)
        scrollView.addSubview(label)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let textWidth = maxWidth - Self.horizontalPadding * 2
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            label.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: Self.verticalPadding
            ),
            label.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: Self.horizontalPadding
            ),
            label.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -Self.horizontalPadding
            ),
            label.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -Self.verticalPadding
            ),
            label.widthAnchor.constraint(equalToConstant: textWidth),
        ])

        recalculatePreferredContentSize()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        recalculatePreferredContentSize()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        recalculatePreferredContentSize()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Covers programmatic dismiss and interactive dismiss; notify at most once.
        guard isBeingDismissed || presentingViewController == nil else { return }
        notifyDismissedIfNeeded()
    }

    func recalculatePreferredContentSize() {
        let maxHeight = Self.defaultMaxHeight(in: view.window)
        let size = Self.fittingContentSize(
            message: message,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            font: label.font ?? UIFont.preferredFont(forTextStyle: .subheadline)
        )
        if preferredContentSize != size {
            preferredContentSize = size
        }
        let uncapped = Self.fittingContentSize(
            message: message,
            maxWidth: maxWidth,
            maxHeight: .greatestFiniteMagnitude,
            font: label.font ?? UIFont.preferredFont(forTextStyle: .subheadline)
        )
        scrollView.isScrollEnabled = uncapped.height > maxHeight + 0.5
    }

    /// Content size for the popover: full text height at `maxWidth`, capped so tall
    /// Dynamic Type can scroll inside the bubble instead of overflowing the screen.
    static func fittingContentSize(
        message: String,
        maxWidth: CGFloat = defaultMaxWidth,
        maxHeight: CGFloat,
        horizontalPadding: CGFloat = horizontalPadding,
        verticalPadding: CGFloat = verticalPadding,
        font: UIFont = UIFont.preferredFont(forTextStyle: .subheadline)
    ) -> CGSize {
        let textWidth = max(1, maxWidth - horizontalPadding * 2)
        let rect = (message as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let contentHeight = ceil(rect.height) + verticalPadding * 2
        return CGSize(width: maxWidth, height: min(contentHeight, maxHeight))
    }

    static func defaultMaxHeight(in window: UIWindow? = nil) -> CGFloat {
        let screenBounds = window?.windowScene?.screen.bounds
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds
            ?? CGRect(x: 0, y: 0, width: 390, height: 844)
        let safeInsets = window?.safeAreaInsets
            ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
        let usable = screenBounds.height - safeInsets.top - safeInsets.bottom
        // Keep the bubble in the safe area; scroll inside if Dynamic Type needs more.
        return max(120, usable * 0.45)
    }

    fileprivate func notifyDismissedIfNeeded() {
        guard !didNotifyDismissed else { return }
        didNotifyDismissed = true
        let callback = onDismissed
        onDismissed = nil
        // UIKit popover teardown leaves VO on the dismissed chrome; announce the change.
        // Callback (AccessibilityFocusState on the SwiftUI (i)) runs next so it wins focus —
        // the UIKit anchor is accessibilityElementsHidden and must not be the target.
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
        DispatchQueue.main.async {
            callback?()
        }
    }
}

private enum AnchoredInfoPopoverRetain {
    static var key: UInt8 = 0
}

private final class AnchoredInfoPopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    /// Keep the popover on iPhone so it stays attached to the tapped control.
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        (presentationController.presentedViewController as? AnchoredInfoPopoverController)?
            .notifyDismissedIfNeeded()
    }
}

/// Invisible UIView behind a SwiftUI control; its bounds are the popover `sourceView`.
struct AnchoredInfoPopoverAnchor: UIViewRepresentable {
    var message: String
    var maxWidth: CGFloat = AnchoredInfoPopoverController.defaultMaxWidth
    var trigger: AnchoredInfoPopoverTrigger
    /// Restores VoiceOver to the SwiftUI (i) button after dismiss (anchor itself is a11y-hidden).
    var onDismissed: (() -> Void)? = nil

    func makeUIView(context: Context) -> AnchoredInfoPopoverAnchorView {
        let view = AnchoredInfoPopoverAnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ uiView: AnchoredInfoPopoverAnchorView, context: Context) {
        uiView.message = message
        uiView.maxWidth = maxWidth
        uiView.onDismissed = onDismissed
        trigger.onDismissed = onDismissed
        trigger.fireImpl = { [weak uiView] in
            uiView?.present()
        }
    }

    static func dismantleUIView(_ uiView: AnchoredInfoPopoverAnchorView, coordinator: ()) {
        uiView.dismissPresentedPopover(animated: false)
        uiView.onDismissed = nil
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: AnchoredInfoPopoverAnchorView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

private extension UIView {
    func pickemsTopPresenter() -> UIViewController? {
        let start: UIViewController?
        if let root = window?.rootViewController {
            start = root
        } else {
            start = enclosingViewController()
        }
        guard var top = start else { return nil }
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        if top.isBeingDismissed {
            return top.presentingViewController
        }
        return top
    }

    func enclosingViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController { return controller }
            responder = next
        }
        return nil
    }
}

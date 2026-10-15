import SwiftUI
import UIKit

/// Veto confirmation for one Selection row.
///
/// `confirmationDialog` on `GroupPicksView` anchored to the first button in the
/// list (the member header) instead of the Veto control that was tapped. Each
/// row owns an anchor view the size of its button and points the popover there.
struct SelectionVetoButton: View {
    let nominationId: String
    let matchup: String
    let votesNeeded: Int
    var voted: Bool
    let onConfirm: () -> Void

    @Environment(\.themePalette) private var theme
    @State private var trigger = SelectionVetoConfirmTrigger()

    var body: some View {
        Button {
            trigger.fire()
        } label: {
            Label(voted ? "Voted" : "Veto", systemImage: "hand.raised")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
        }
        .disabled(voted)
        .accessibilityHint(voted ? "You already voted" : "Vote to remove this Selection")
        .background {
            SelectionVetoConfirmAnchor(
                nominationId: nominationId,
                message: SelectionVetoPrompt.message(matchup: matchup, votesNeeded: votesNeeded),
                trigger: trigger,
                onConfirm: onConfirm
            )
            .allowsHitTesting(false)
        }
    }
}

/// Holds the present closure for one row so the SwiftUI button and its anchor stay in sync.
@MainActor
fileprivate final class SelectionVetoConfirmTrigger {
    fileprivate var fireImpl: (() -> Void)?

    func fire() {
        fireImpl?()
    }
}

/// UIView whose bounds are the Veto button. The confirmation popover uses this as `sourceView`.
final class SelectionVetoConfirmAnchorView: UIView {
    var promptMessage = ""
    var onConfirm: () -> Void = {}

    func makeAlert() -> UIAlertController {
        let alert = UIAlertController(
            title: SelectionVetoPrompt.title,
            message: promptMessage,
            preferredStyle: .actionSheet
        )
        let confirm = onConfirm
        alert.addAction(UIAlertAction(title: "Veto", style: .destructive) { _ in
            Task { @MainActor in
                confirm()
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        SelectionVetoPrompt.anchor(alert, to: self)
        return alert
    }

    func present(animated: Bool = true) {
        guard window != nil else { return }
        guard let presenter = pickemsTopPresenter(), presenter.presentedViewController == nil else { return }
        presenter.present(makeAlert(), animated: animated)
    }
}

private struct SelectionVetoConfirmAnchor: UIViewRepresentable {
    var nominationId: String
    var message: String
    var trigger: SelectionVetoConfirmTrigger
    var onConfirm: () -> Void

    func makeUIView(context: Context) -> SelectionVetoConfirmAnchorView {
        let view = SelectionVetoConfirmAnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ uiView: SelectionVetoConfirmAnchorView, context: Context) {
        uiView.promptMessage = message
        uiView.onConfirm = onConfirm
        uiView.accessibilityIdentifier = SelectionVetoPrompt.anchorIdentifier(nominationId: nominationId)
        trigger.fireImpl = { [weak uiView] in
            uiView?.present()
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: SelectionVetoConfirmAnchorView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

extension SelectionVetoPrompt {
    /// Popover source is `source` (the tapped Veto control), in that view's own coordinates.
    static func anchor(_ alert: UIAlertController, to source: UIView) {
        alert.modalPresentationStyle = .popover
        let delegate = SelectionVetoPopoverDelegate()
        objc_setAssociatedObject(
            alert,
            &SelectionVetoPopoverRetain.key,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        guard let popover = alert.popoverPresentationController else { return }
        popover.sourceView = source
        popover.sourceRect = source.bounds
        popover.permittedArrowDirections = [.up, .down]
        popover.delegate = delegate
    }
}

private enum SelectionVetoPopoverRetain {
    static var key: UInt8 = 0
}

final class SelectionVetoPopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    /// Keep the popover on iPhone so it stays attached to the tapped Veto button.
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
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

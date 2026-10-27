import SwiftUI
import UIKit

/// Confirmation action sheet whose popover source is the control that was tapped.
/// iPhone keeps the popover (adaptive style `.none`) so it does not become an unanchored sheet.
struct AnchoredActionConfirm<Label: View>: View {
    let title: String
    let message: String
    let confirmTitle: String
    var destructive: Bool = true
    let onConfirm: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var trigger = AnchoredActionConfirmTrigger()

    var body: some View {
        Button {
            trigger.fire()
        } label: {
            label()
        }
        .background {
            AnchoredActionConfirmAnchor(
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                destructive: destructive,
                trigger: trigger,
                onConfirm: onConfirm
            )
            .allowsHitTesting(false)
        }
    }
}

@MainActor
final class AnchoredActionConfirmTrigger {
    fileprivate var fireImpl: (() -> Void)?

    func fire() {
        fireImpl?()
    }
}

final class AnchoredActionConfirmAnchorView: UIControl {
    var promptTitle = ""
    var promptMessage = ""
    var confirmTitle = "Confirm"
    var destructive = true
    var onConfirm: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        addAction(UIAction { [weak self] _ in
            self?.present()
        }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addAction(UIAction { [weak self] _ in
            self?.present()
        }, for: .touchUpInside)
    }

    func makeAlert() -> UIAlertController {
        let alert = UIAlertController(title: promptTitle, message: promptMessage, preferredStyle: .actionSheet)
        let confirm = onConfirm
        let run: () -> Void = {
            Task { @MainActor in
                confirm()
            }
            return
        }
        alert.addAction(UIAlertAction(title: confirmTitle, style: destructive ? .destructive : .default) { _ in
            run()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        AnchoredActionConfirmPrompt.anchor(alert, to: self)
        return alert
    }

    func present(animated: Bool = true) {
        guard window != nil else { return }
        guard let presenter = pickemsConfirmPresenter(), presenter.presentedViewController == nil else { return }
        presenter.present(makeAlert(), animated: animated)
    }
}

enum AnchoredActionConfirmPrompt {
    static func anchor(_ alert: UIAlertController, to source: UIView) {
        alert.modalPresentationStyle = .popover
        let delegate = AnchoredActionConfirmDelegate()
        objc_setAssociatedObject(
            alert,
            &AnchoredActionConfirmRetain.key,
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

private enum AnchoredActionConfirmRetain {
    static var key: UInt8 = 0
}

private final class AnchoredActionConfirmDelegate: NSObject, UIPopoverPresentationControllerDelegate {
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

private struct AnchoredActionConfirmAnchor: UIViewRepresentable {
    var title: String
    var message: String
    var confirmTitle: String
    var destructive: Bool
    var trigger: AnchoredActionConfirmTrigger
    var onConfirm: () -> Void

    func makeUIView(context: Context) -> AnchoredActionConfirmAnchorView {
        let view = AnchoredActionConfirmAnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ uiView: AnchoredActionConfirmAnchorView, context: Context) {
        uiView.promptTitle = title
        uiView.promptMessage = message
        uiView.confirmTitle = confirmTitle
        uiView.destructive = destructive
        uiView.onConfirm = onConfirm
        trigger.fireImpl = { [weak uiView] in
            uiView?.present()
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: AnchoredActionConfirmAnchorView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

private extension UIView {
    func pickemsConfirmPresenter() -> UIViewController? {
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

import MessageUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MessageComposeView: UIViewControllerRepresentable {
    let body: String
    var image: UIImage?
    var fileName: String = "pickems-results.jpg"
    var onFinish: (() -> Void)?

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (() -> Void)?

        init(onFinish: (() -> Void)?) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            onFinish?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.body = body

        if MFMessageComposeViewController.canSendAttachments(),
           let image,
           let data = image.jpegData(compressionQuality: 0.88) {
            controller.addAttachmentData(
                data,
                typeIdentifier: UTType.jpeg.identifier,
                filename: fileName
            )
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {
        if uiViewController.body?.isEmpty != false {
            uiViewController.body = body
        }
    }
}

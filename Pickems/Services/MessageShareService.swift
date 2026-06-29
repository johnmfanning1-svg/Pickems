import MessageUI
import UIKit

enum MessageShareService {
    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    static func openSMSFallback(body: String) {
        guard let url = MessageURLBuilder.smsURL(body: body) else { return }
        UIApplication.shared.open(url)
    }
}

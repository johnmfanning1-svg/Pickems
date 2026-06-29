import Foundation

enum AppShareContent {
    static func inviteMessage(leagueName: String? = nil) -> String {
        AppShareTextBuilder.inviteMessage(leagueName: leagueName)
    }

    static func inviteTweet(leagueName: String? = nil) -> String {
        AppShareTextBuilder.inviteTweet(leagueName: leagueName)
    }
}

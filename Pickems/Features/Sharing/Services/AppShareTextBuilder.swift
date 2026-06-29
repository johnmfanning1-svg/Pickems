import Foundation

enum AppShareTextBuilder {
    static func inviteMessage(leagueName: String? = nil) -> String {
        var lines = ["Join our CFB pick'em league on Pickems! 🏈"]

        if let leagueName, !leagueName.isEmpty {
            lines.append("League: \(leagueName)")
        }

        lines.append("Live game data, private standings, and weekly bragging rights.")
        lines.append(AppConfig.appStoreURL)
        return lines.joined(separator: "\n")
    }

    static func inviteTweet(leagueName: String? = nil) -> String {
        var lines = ["Running our CFB pick'em league on Pickems 🏈"]

        if let leagueName, !leagueName.isEmpty {
            lines.append("League: \(leagueName)")
        }

        lines.append("Private picks, live ESPN data, and standings that settle arguments.")
        lines.append(AppConfig.appPromoURL)
        lines.append("\(AppConfig.cfbHashtag) \(AppConfig.appHashtag)")
        return lines.joined(separator: "\n")
    }
}

import Foundation

enum ScreenShareTextBuilder {
    static func caption(leagueName: String, contextLine: String, groupId: String?) -> String {
        var lines = ["\(leagueName) — \(contextLine)"]
        if let groupId, !groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(AppConfig.leagueShareURL(groupId: groupId))
        }
        lines.append("Get CFB Pickems: \(AppConfig.appStoreURL)")
        return lines.joined(separator: "\n")
    }
}
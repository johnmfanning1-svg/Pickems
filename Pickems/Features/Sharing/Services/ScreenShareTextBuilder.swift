import Foundation

enum ScreenShareTextBuilder {
    static func caption(leagueName: String, contextLine: String) -> String {
        "\(leagueName) — \(contextLine)\nGet CFB Pickems: \(AppConfig.appStoreURL)"
    }
}
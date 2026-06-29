import Foundation

enum AvatarColors {
    static let paletteHex = [
        "#DC2626", "#3366CC", "#26A65B", "#D98E04",
        "#8C4FCF", "#4DB8CC"
    ]

    static func randomHex() -> String {
        paletteHex.randomElement() ?? "#DC2626"
    }
}

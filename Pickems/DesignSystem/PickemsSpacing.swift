import CoreGraphics

/// Shared gaps for Home and the Pickems sheet.
/// Screen inset stays `md` (16). Section gaps use `lg`. Inside a section, use `sm`.
enum PickemsSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

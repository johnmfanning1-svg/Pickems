import Foundation

extension Int {
    /// Plain digit year string with no locale grouping separators (e.g. `"2026"`, never `"2,026"`).
    /// Prefer this when interpolating years into SwiftUI `Text` / `Label` / titles, which use `LocalizedStringKey`
    /// and otherwise format `Int` with grouping.
    var pickemsYearString: String {
        String(self)
    }
}

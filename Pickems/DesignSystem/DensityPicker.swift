import SwiftUI

/// Segmented Comfortable / Dense control shared by the league chart and the Pickems list.
///
/// Each surface keeps its own `AppStorage` key. The chart defaults to Dense; Pickems cards
/// default to Comfortable so today's game cards stay the first-run look.
struct DensityPicker: View {
    static let leagueChartStorageKey = "leaguePickems.chartIsDense"
    static let pickemsCardsStorageKey = "pickems.cardsAreDense"
    /// Chart opens Dense, matching the previous `@AppStorage` default.
    static let leagueChartDefaultsDense = true
    /// Pickems cards open Comfortable.
    static let pickemsCardsDefaultDense = false

    @Binding var isDense: Bool
    var accessibilityLabel: String
    var hint: String

    var body: some View {
        Picker(accessibilityLabel, selection: $isDense) {
            Text("Comfortable").tag(false)
            Text("Dense").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 210)
        .labelsHidden()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isDense ? "Dense" : "Comfortable")
        .accessibilityHint(hint)
    }
}

/// Reads and writes the same `UserDefaults` keys `AppStorage` uses for `DensityPicker`.
enum DensityPreferenceStore {
    static func isDense(forKey key: String, default defaultValue: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    static func setDense(_ isDense: Bool, forKey key: String, defaults: UserDefaults = .standard) {
        defaults.set(isDense, forKey: key)
    }
}

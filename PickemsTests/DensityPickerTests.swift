import Foundation
import Testing
@testable import Pickems

struct DensityPickerTests {
    @Test func chartAndPickemsUseSeparateKeys() {
        #expect(DensityPicker.leagueChartStorageKey == "leaguePickems.chartIsDense")
        #expect(DensityPicker.pickemsCardsStorageKey == "pickems.cardsAreDense")
        #expect(DensityPicker.leagueChartStorageKey != DensityPicker.pickemsCardsStorageKey)
    }

    @Test func pickemsCardsDefaultToComfortableAndTheChartDefaultsToDense() {
        #expect(DensityPicker.pickemsCardsDefaultDense == false)
        #expect(DensityPicker.leagueChartDefaultsDense == true)
    }

    @Test func bindingWritesThePickemsKeyWithoutTouchingTheChartKey() {
        let suite = "pickems.density.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(
            DensityPreferenceStore.isDense(
                forKey: DensityPicker.pickemsCardsStorageKey,
                default: DensityPicker.pickemsCardsDefaultDense,
                defaults: defaults
            ) == false
        )
        #expect(defaults.object(forKey: DensityPicker.pickemsCardsStorageKey) == nil)
        #expect(defaults.object(forKey: DensityPicker.leagueChartStorageKey) == nil)

        DensityPreferenceStore.setDense(true, forKey: DensityPicker.pickemsCardsStorageKey, defaults: defaults)

        #expect(
            DensityPreferenceStore.isDense(
                forKey: DensityPicker.pickemsCardsStorageKey,
                default: DensityPicker.pickemsCardsDefaultDense,
                defaults: defaults
            ) == true
        )
        #expect(defaults.object(forKey: DensityPicker.leagueChartStorageKey) == nil)

        DensityPreferenceStore.setDense(false, forKey: DensityPicker.pickemsCardsStorageKey, defaults: defaults)
        #expect(
            DensityPreferenceStore.isDense(
                forKey: DensityPicker.pickemsCardsStorageKey,
                default: true,
                defaults: defaults
            ) == false
        )
    }
}

import Foundation
import Testing
@testable import Pickems

struct WidgetDisplayGroupPickerTests {
    @Test func unpinnedSelectionShowsFollowCurrentLeague() {
        #expect(WidgetDisplayGroupPicker.followLabel == "Follow current league")
        #expect(WidgetDisplayGroupPicker.selectionTag(savedId: nil) == WidgetDisplayGroupPicker.followTag)
        #expect(WidgetDisplayGroupPicker.selectionTag(savedId: "") == WidgetDisplayGroupPicker.followTag)
        #expect(WidgetDisplayGroupPicker.selectionTag(savedId: nil) != "open-league")
    }

    @Test func pinnedSelectionShowsTheSavedLeague() {
        #expect(WidgetDisplayGroupPicker.selectionTag(savedId: "pinned") == "pinned")
        #expect(WidgetDisplayGroupPicker.selectionTag(savedId: "pinned") != WidgetDisplayGroupPicker.followTag)
        #expect(WidgetDisplayGroupPicker.selectionTag(savedId: "pinned") != "open-league")
    }

    @Test func followClearsThePinAndALeaguePinsIt() {
        let suite = "pickems.widget-picker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("pinned", forKey: PickemsAppGroup.displayGroupIdKey)

        #expect(
            WidgetDisplayGroupPicker.apply(
                tag: WidgetDisplayGroupPicker.followTag,
                memberIds: ["pinned", "other"],
                defaults: defaults
            )
        )
        #expect(defaults.string(forKey: PickemsAppGroup.displayGroupIdKey) == nil)
        #expect(
            WidgetDisplayGroupPicker.selectionTag(
                savedId: defaults.string(forKey: PickemsAppGroup.displayGroupIdKey)
            ) == WidgetDisplayGroupPicker.followTag
        )

        #expect(
            WidgetDisplayGroupPicker.apply(
                tag: "other",
                memberIds: ["pinned", "other"],
                defaults: defaults
            )
        )
        #expect(defaults.string(forKey: PickemsAppGroup.displayGroupIdKey) == "other")
        #expect(WidgetDisplayGroupPicker.selectionTag(savedId: "other") == "other")
    }

    @Test func unknownSelectionLeavesThePin() {
        let suite = "pickems.widget-picker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("pinned", forKey: PickemsAppGroup.displayGroupIdKey)

        #expect(
            WidgetDisplayGroupPicker.pin(for: "missing", memberIds: ["pinned"]) == nil
        )
        #expect(
            !WidgetDisplayGroupPicker.apply(
                tag: "missing",
                memberIds: ["pinned"],
                defaults: defaults
            )
        )
        #expect(defaults.string(forKey: PickemsAppGroup.displayGroupIdKey) == "pinned")
        #expect(
            WidgetDisplayGroupPicker.pin(
                for: WidgetDisplayGroupPicker.followTag,
                memberIds: ["pinned"]
            ) == WidgetDisplayGroupPicker.Pin.clear
        )
        #expect(
            WidgetDisplayGroupPicker.pin(for: "pinned", memberIds: ["pinned"])
                == WidgetDisplayGroupPicker.Pin.pin("pinned")
        )
    }
}

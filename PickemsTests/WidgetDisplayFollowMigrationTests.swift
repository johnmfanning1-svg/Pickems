import Foundation
import Testing
@testable import Pickems

struct WidgetDisplayFollowMigrationTests {
    @Test func matchingPinClearsOnce() {
        let fixture = MigrationDefaults()
        fixture.defaults.set("core", forKey: PickemsAppGroup.displayGroupIdKey)

        #expect(
            WidgetDisplayFollowMigration.decision(
                savedId: "core",
                selectedGroupId: "core",
                completed: false
            ) == WidgetDisplayFollowMigration.Decision(clearPin: true, markCompleted: true)
        )
        #expect(WidgetDisplayFollowMigration.apply(selectedGroupId: "core", defaults: fixture.defaults))
        #expect(fixture.defaults.string(forKey: PickemsAppGroup.displayGroupIdKey) == nil)
        #expect(fixture.defaults.bool(forKey: WidgetDisplayFollowMigration.completedKey))

        fixture.defaults.set("core", forKey: PickemsAppGroup.displayGroupIdKey)
        #expect(!WidgetDisplayFollowMigration.apply(selectedGroupId: "core", defaults: fixture.defaults))
        #expect(fixture.defaults.string(forKey: PickemsAppGroup.displayGroupIdKey) == "core")
        #expect(
            WidgetDisplayFollowMigration.decision(
                savedId: "core",
                selectedGroupId: "core",
                completed: true
            ) == WidgetDisplayFollowMigration.Decision(clearPin: false, markCompleted: false)
        )
    }

    @Test func differentPinStays() {
        let fixture = MigrationDefaults()
        fixture.defaults.set("other", forKey: PickemsAppGroup.displayGroupIdKey)

        #expect(
            WidgetDisplayFollowMigration.decision(
                savedId: "other",
                selectedGroupId: "core",
                completed: false
            ) == WidgetDisplayFollowMigration.Decision(clearPin: false, markCompleted: true)
        )
        #expect(!WidgetDisplayFollowMigration.apply(selectedGroupId: "core", defaults: fixture.defaults))
        #expect(fixture.defaults.string(forKey: PickemsAppGroup.displayGroupIdKey) == "other")
        #expect(fixture.defaults.bool(forKey: WidgetDisplayFollowMigration.completedKey))
    }

    @Test func missingPinCompletesWithoutCreatingOne() {
        let fixture = MigrationDefaults()

        #expect(
            WidgetDisplayFollowMigration.decision(
                savedId: nil,
                selectedGroupId: "core",
                completed: false
            ) == WidgetDisplayFollowMigration.Decision(clearPin: false, markCompleted: true)
        )
        #expect(
            WidgetDisplayFollowMigration.decision(
                savedId: "",
                selectedGroupId: "core",
                completed: false
            ) == WidgetDisplayFollowMigration.Decision(clearPin: false, markCompleted: true)
        )
        #expect(!WidgetDisplayFollowMigration.apply(selectedGroupId: "core", defaults: fixture.defaults))
        #expect(fixture.defaults.object(forKey: PickemsAppGroup.displayGroupIdKey) == nil)
        #expect(fixture.defaults.bool(forKey: WidgetDisplayFollowMigration.completedKey))
    }

    @Test func waitsUntilTheSelectedLeagueIsKnown() {
        let fixture = MigrationDefaults()
        fixture.defaults.set("core", forKey: PickemsAppGroup.displayGroupIdKey)

        #expect(
            WidgetDisplayFollowMigration.decision(
                savedId: "core",
                selectedGroupId: nil,
                completed: false
            ) == WidgetDisplayFollowMigration.Decision(clearPin: false, markCompleted: false)
        )
        #expect(!WidgetDisplayFollowMigration.apply(selectedGroupId: nil, defaults: fixture.defaults))
        #expect(!WidgetDisplayFollowMigration.apply(selectedGroupId: "", defaults: fixture.defaults))
        #expect(fixture.defaults.string(forKey: PickemsAppGroup.displayGroupIdKey) == "core")
        #expect(!fixture.defaults.bool(forKey: WidgetDisplayFollowMigration.completedKey))

        #expect(WidgetDisplayFollowMigration.apply(selectedGroupId: "core", defaults: fixture.defaults))
        #expect(fixture.defaults.string(forKey: PickemsAppGroup.displayGroupIdKey) == nil)
        #expect(fixture.defaults.bool(forKey: WidgetDisplayFollowMigration.completedKey))
    }
}

private final class MigrationDefaults {
    let suite: String
    let defaults: UserDefaults

    init() {
        suite = "pickems.widget-follow.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }
}

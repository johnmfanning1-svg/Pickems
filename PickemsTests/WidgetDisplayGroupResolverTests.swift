import Foundation
import Testing
@testable import Pickems

struct WidgetDisplayGroupResolverTests {
    @Test func savedIdStillAMemberWins() {
        #expect(
            WidgetDisplayGroupResolver.resolve(
                savedId: "b",
                selectedGroupId: "a",
                groupIds: ["a", "b"]
            ) == "b"
        )
    }

    @Test func staleSavedIdFallsBackToSelected() {
        #expect(
            WidgetDisplayGroupResolver.resolve(
                savedId: "deleted",
                selectedGroupId: "a",
                groupIds: ["a", "b"]
            ) == "a"
        )
    }

    @Test func staleSavedIdFallsBackToFirstWhenSelectedMissing() {
        #expect(
            WidgetDisplayGroupResolver.resolve(
                savedId: "gone",
                selectedGroupId: "also-gone",
                groupIds: ["a", "b"]
            ) == "a"
        )
        #expect(
            WidgetDisplayGroupResolver.resolve(
                savedId: "gone",
                selectedGroupId: nil,
                groupIds: ["a", "b"]
            ) == "a"
        )
    }

    @Test func emptyGroupsReturnsNil() {
        #expect(
            WidgetDisplayGroupResolver.resolve(
                savedId: "a",
                selectedGroupId: "a",
                groupIds: []
            ) == nil
        )
        #expect(
            WidgetDisplayGroupResolver.resolve(
                savedId: nil,
                selectedGroupId: nil,
                groupIds: []
            ) == nil
        )
    }

    @Test func nilSavedUsesSelectedThenFirst() {
        #expect(
            WidgetDisplayGroupResolver.resolve(
                savedId: nil,
                selectedGroupId: "b",
                groupIds: ["a", "b"]
            ) == "b"
        )
        #expect(
            WidgetDisplayGroupResolver.resolve(
                savedId: nil,
                selectedGroupId: nil,
                groupIds: ["a", "b"]
            ) == "a"
        )
    }
}

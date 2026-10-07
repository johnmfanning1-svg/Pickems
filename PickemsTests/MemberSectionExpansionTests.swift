import Testing
@testable import Pickems

struct MemberSectionExpansionTests {
    @Test func collapsedOnlyOnSelectionsTabDuringSelections() {
        #expect(MemberSectionExpansion.startsCollapsed(forceNominatingDisplay: true, weekStatus: .selection))
        #expect(!MemberSectionExpansion.startsCollapsed(forceNominatingDisplay: true, weekStatus: .locked))
        #expect(!MemberSectionExpansion.startsCollapsed(forceNominatingDisplay: true, weekStatus: .picking))
        #expect(!MemberSectionExpansion.startsCollapsed(forceNominatingDisplay: false, weekStatus: .selection))
        #expect(!MemberSectionExpansion.startsCollapsed(forceNominatingDisplay: true, weekStatus: nil))
    }

    @Test func tapExpandsACollapsedCard() {
        var state = MemberSectionExpansion()
        #expect(state.isCollapsed("a", defaultCollapsed: true))
        state.toggle("a", defaultCollapsed: true)
        #expect(!state.isCollapsed("a", defaultCollapsed: true))
        #expect(state.isCollapsed("b", defaultCollapsed: true))
        state.toggle("a", defaultCollapsed: true)
        #expect(state.isCollapsed("a", defaultCollapsed: true))
    }

    @Test func openByDefaultElsewhere() {
        var state = MemberSectionExpansion()
        #expect(!state.isCollapsed("a", defaultCollapsed: false))
        state.toggle("a", defaultCollapsed: false)
        #expect(state.isCollapsed("a", defaultCollapsed: false))
    }

    @Test func changingDefaultStartsFresh() {
        var state = MemberSectionExpansion()
        state.toggle("a", defaultCollapsed: true)
        #expect(!state.isCollapsed("a", defaultCollapsed: true))
        // Selections close: the default flips to open and the old tap no longer applies.
        #expect(!state.isCollapsed("a", defaultCollapsed: false))
        #expect(!state.isCollapsed("b", defaultCollapsed: false))
    }
}

import Foundation
import Testing
@testable import Pickems

struct SpreadLineCopyTests {
    @Test func omitsLiveWhenMissingOrBlank() {
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: nil) == nil)
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: "  ") == nil)
        #expect(SpreadLineCopy.caption(locked: "OSU -7.0", live: nil) == "OSU -7.0")
    }

    @Test func omitsLiveWhenItMatchesTheLockedLine() {
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: "OSU -7.0") == nil)
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: "OSU -7") == nil)
        #expect(SpreadLineCopy.caption(locked: "OSU -7.0", live: "OSU -7.0") == "OSU -7.0")
    }

    @Test func includesLiveWhenTheLineMoved() {
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: "OSU -6.5") == "OSU -6.5")
        #expect(SpreadLineCopy.caption(locked: "OSU -7.0", live: "OSU -6.5") == "OSU -7.0 (OSU -6.5)")
    }

    @Test func accessibilityMentionsLockedAndLive() {
        let label = SpreadLineCopy.accessibilityLabel(
            locked: "OSU -7.0",
            live: "OSU -6.5",
            isLocked: true
        )
        #expect(label.contains("Locked Pickems spread OSU -7.0"))
        #expect(label.contains("Live spread OSU -6.5, for reference"))
    }
}

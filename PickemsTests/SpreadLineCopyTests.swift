import Foundation
import Testing
@testable import Pickems

struct SpreadLineCopyTests {
    @Test func omitsReferenceWhenMissingOrBlank() {
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: nil) == nil)
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: "  ") == nil)
        #expect(SpreadLineCopy.referenceCaption(locked: "OSU -7.0", live: nil, isFinal: false) == nil)
        #expect(SpreadLineCopy.caption(locked: "OSU -7.0", live: nil) == "OSU -7.0")
    }

    @Test func omitsReferenceWhenItMatchesTheLockedLine() {
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: "OSU -7.0") == nil)
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: "OSU -7") == nil)
        #expect(SpreadLineCopy.referenceCaption(locked: "OSU -7.0", live: "OSU -7.0", isFinal: false) == nil)
        #expect(SpreadLineCopy.caption(locked: "OSU -7.0", live: "OSU -6.5") == "OSU -7.0")
    }

    @Test func currentLineCaptionWhenTheLineMoved() {
        #expect(SpreadLineCopy.liveReference(locked: "OSU -7.0", live: "OSU -6.5") == "OSU -6.5")
        #expect(
            SpreadLineCopy.referenceCaption(locked: "OSU -7.0", live: "OSU -6.5", isFinal: false)
                == "Current line: -6.5"
        )
    }

    @Test func closingLineCaptionOnceFinal() {
        #expect(
            SpreadLineCopy.referenceCaption(locked: "LSU -7.5", live: "LSU -7.0", isFinal: true)
                == "Closing line: -7.0"
        )
    }

    @Test func neverUsesParentheticalFormat() {
        let caption = SpreadLineCopy.caption(locked: "LSU -7.5", live: "LSU -7.0")
        #expect(caption == "LSU -7.5")
        #expect(!caption.contains("("))
        #expect(
            SpreadLineCopy.referenceCaption(locked: "LSU -7.5", live: "LSU -7.0", isFinal: false)
                == "Current line: -7.0"
        )
    }

    @Test func infoMessageForMovedLineBeforeFinal() {
        let message = SpreadLineCopy.infoMessage(locked: "LSU -7.5", live: "LSU -7.0", isFinal: false)
        #expect(
            message
                == "Your pick is graded at LSU -7.5, the line when picks locked. Vegas has since moved it to -7.0. That's for reference only and doesn't change your result."
        )
    }

    @Test func infoMessageForMovedLineAfterFinal() {
        let message = SpreadLineCopy.infoMessage(locked: "LSU -7.5", live: "LSU -7.0", isFinal: true)
        #expect(
            message
                == "Your pick is graded at LSU -7.5, the line when picks locked. The line closed at -7.0. That's for reference only and doesn't change your result."
        )
    }

    @Test func infoMessageNilWhenLineUnchanged() {
        #expect(SpreadLineCopy.infoMessage(locked: "OSU -7.0", live: "OSU -7.0", isFinal: false) == nil)
        #expect(SpreadLineCopy.infoMessage(locked: "OSU -7.0", live: "  ", isFinal: false) == nil)
    }

    @Test func pickEmWordingInInfoMessage() {
        let message = SpreadLineCopy.infoMessage(locked: "ALA -0.0", live: "ALA -3.0", isFinal: false)
        #expect(message?.contains("ALA even (pick'em)") == true)
        #expect(message?.contains("Vegas has since moved it to -3.0") == true)
        #expect(
            SpreadLineCopy.referenceCaption(locked: "ALA -0.0", live: "ALA -3.0", isFinal: false)
                == "Current line: -3.0"
        )
        #expect(
            SpreadLineCopy.referenceCaption(locked: "ALA -3.0", live: "ALA -0.0", isFinal: false)
                == "Current line: PK"
        )
    }

    @Test func accessibilityMentionsLockedAndCurrent() {
        let label = SpreadLineCopy.accessibilityLabel(
            locked: "LSU -7.5",
            live: "LSU -7.0",
            isLocked: true,
            isFinal: false
        )
        #expect(label.contains("Locked line LSU minus 7.5"))
        #expect(label.contains("Current line minus 7.0"))
    }

    @Test func accessibilityUsesClosingOnceFinal() {
        let label = SpreadLineCopy.accessibilityLabel(
            locked: "OSU -7.0",
            live: "OSU -6.5",
            isLocked: true,
            isFinal: true
        )
        #expect(label.contains("Closing line minus 6.5"))
        #expect(!label.contains("Current line"))
    }
}

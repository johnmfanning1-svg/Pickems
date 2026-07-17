import Foundation
import Testing
@testable import Pickems

struct DisplayNameRulesTests {
    @Test func acceptsNicknamesAndHandles() {
        #expect(DisplayNameRules.validate("big_mike").isSuccess)
        #expect(DisplayNameRules.validate("Coach J").isSuccess)
        #expect(DisplayNameRules.validate("roll-tide").isSuccess)
        #expect(DisplayNameRules.validate("a.b").isSuccess)
        #expect(DisplayNameRules.validate("ab").isSuccess == false)
    }

    @Test func rejectsInvalidAndTooLong() {
        #expect(DisplayNameRules.validate("").isSuccess == false)
        #expect(DisplayNameRules.validate("hi").isSuccess == false)
        #expect(DisplayNameRules.validate(String(repeating: "a", count: 21)).isSuccess == false)
        #expect(DisplayNameRules.validate("bad!name").isSuccess == false)
        #expect(DisplayNameRules.validate("@@@").isSuccess == false)
    }

    @Test func uniquenessIsCaseInsensitive() {
        #expect(
            DisplayNameRules.uniquenessKey(for: "Big Mike")
                == DisplayNameRules.uniquenessKey(for: "big mike")
        )
        #expect(DisplayNameRules.normalize("  Cool   Nick  ") == "Cool Nick")
    }
}

private extension Result where Failure == DisplayNameRules.ValidationError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

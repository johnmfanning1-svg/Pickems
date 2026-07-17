import Foundation
import Testing
@testable import Pickems

struct DisplayNameRulesTests {
    @Test func acceptsUsernames() {
        #expect(DisplayNameRules.validate("big_mike").isSuccess)
        #expect(DisplayNameRules.validate("rolltide").isSuccess)
        #expect(DisplayNameRules.validate("a_b").isSuccess)
        #expect(DisplayNameRules.validate("ab").isSuccess == false)
    }

    @Test func rejectsInvalidUsernames() {
        #expect(DisplayNameRules.validate("").isSuccess == false)
        #expect(DisplayNameRules.validate("Coach J").isSuccess == false)
        #expect(DisplayNameRules.validate("bad-name").isSuccess == false)
        #expect(DisplayNameRules.validate("bad!name").isSuccess == false)
        #expect(DisplayNameRules.validate(String(repeating: "a", count: 21)).isSuccess == false)
    }

    @Test func uniquenessIsCaseInsensitive() {
        #expect(
            DisplayNameRules.uniquenessKey(for: "BigMike")
                == DisplayNameRules.uniquenessKey(for: "bigmike")
        )
    }

    @Test func personNamesRequireLetters() {
        #expect(PersonNameRules.validate("John", field: "first name").isSuccess)
        #expect(PersonNameRules.validate("O'Neil", field: "last name").isSuccess)
        #expect(PersonNameRules.validate("", field: "first name").isSuccess == false)
        #expect(PersonNameRules.validate("Ann2", field: "first name").isSuccess == false)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

import Foundation
import Testing
@testable import Pickems

struct OpenWeekEarlyPromptTests {
    @Test func earlyButtonTitleMatchesConfirmAction() {
        #expect(OpenWeekEarlyPrompt.earlyButtonTitle == "Lock Selections Early, Start Pickems")
        #expect(OpenWeekEarlyPrompt.earlyConfirmTitle.contains("Lock Selections"))
        #expect(OpenWeekEarlyPrompt.earlyConfirmMessage.localizedCaseInsensitiveContains("Selections"))
        #expect(OpenWeekEarlyPrompt.earlyAccessibilityLabel == OpenWeekEarlyPrompt.earlyButtonTitle)
    }

    @Test func openWithGamesTitlePluralizes() {
        #expect(OpenWeekEarlyPrompt.openWithGamesButtonTitle(uniqueGames: 1) == "Open With 1 Game")
        #expect(OpenWeekEarlyPrompt.openWithGamesButtonTitle(uniqueGames: 3) == "Open With 3 Games")
        #expect(OpenWeekEarlyPrompt.openWithGamesConfirmTitle(uniqueGames: 2) == "Open With 2 Games?")
    }
}
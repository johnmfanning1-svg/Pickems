import XCTest

final class PickemsUITests: XCTestCase {
    func testLaunchShowsSignIn() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Pickems"].waitForExistence(timeout: 5))
    }
}

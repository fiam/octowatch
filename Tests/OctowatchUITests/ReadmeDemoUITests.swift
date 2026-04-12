import XCTest

@MainActor
final class ReadmeDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateRunningOctowatchIfNeeded()
    }

    func testReadmeDemoFixtureShowsRichInboxAndDetail() async throws {
        let app = launchFixture(named: "readme-demo")

        XCTAssertTrue(
            app.staticTexts["Polish the first-run setup experience"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["View on GitHub"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Approve production deployment"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Security alert in dependency snapshot"].waitForExistence(timeout: 5))
    }
}

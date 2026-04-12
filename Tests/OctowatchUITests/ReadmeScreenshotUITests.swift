import XCTest

@MainActor
final class ReadmeScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateRunningOctowatchIfNeeded()
    }

    func testCaptureReadmeMainWindow() async throws {
        let app = launchFixture(named: "readme-demo")

        XCTAssertTrue(
            app.staticTexts["Polish the first-run setup experience"]
                .waitForExistence(timeout: 5)
        )

        add(makeWindowScreenshotAttachment(named: "readme-main-window", for: app))
    }

    func testCaptureReadmeOnboardingWindow() async throws {
        let app = launchFixture(named: "first-run-gh-ready")

        XCTAssertTrue(app.staticTexts["Welcome to Octowatch"].waitForExistence(timeout: 5))

        add(makeWindowScreenshotAttachment(named: "readme-onboarding", for: app))
    }
}

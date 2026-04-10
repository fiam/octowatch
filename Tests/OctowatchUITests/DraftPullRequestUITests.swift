import XCTest

@MainActor
final class DraftPullRequestUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateRunningOctowatchIfNeeded()
    }

    func testDraftAuthoredPullRequestShowsReadyForReviewAction() async throws {
        let app = XCUIApplication()
        app.launchEnvironment["OCTOWATCH_UI_TEST_FIXTURE"] = "draft-authored-pull-request"
        app.launch()

        XCTAssertTrue(app.staticTexts["Draft pull request"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ready-for-review-button"].waitForExistence(timeout: 5))
    }
}

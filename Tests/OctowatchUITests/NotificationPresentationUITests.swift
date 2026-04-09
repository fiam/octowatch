import XCTest

@MainActor
final class NotificationPresentationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        if app.state != .notRunning {
            app.terminate()
        }
    }

    func testSecurityAlertNotificationUsesSecurityAlertPresentation() async throws {
        let app = launchFixture(named: "notification-security-alert")

        let sidebarTitle = app.staticTexts["sidebar-item-title-fixture-security-alert"]

        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 5))

        sidebarTitle.click()

        XCTAssertTrue(
            app.staticTexts["Your repository has dependencies with security vulnerabilities"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["detail-evidence-title-target"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["detail-evidence-title-security-alert"].exists)
        XCTAssertFalse(app.staticTexts["New comment"].exists)
    }

    func testReadSecurityAlertStillAppearsInInbox() async throws {
        let app = launchFixture(named: "notification-security-alert-read")

        let sidebarTitle = app.staticTexts["sidebar-item-title-fixture-security-alert-read"]

        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 5))

        sidebarTitle.click()

        XCTAssertTrue(
            app.staticTexts["Your repository has dependencies with security vulnerabilities"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["detail-evidence-title-security-alert"].exists)
    }

    private func launchFixture(named fixtureName: String) -> XCUIApplication {
        let app = XCUIApplication()
        if app.state != .notRunning {
            app.terminate()
        }
        app.launchEnvironment["OCTOWATCH_UI_TEST_FIXTURE"] = fixtureName
        app.launch()
        return app
    }
}

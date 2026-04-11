import XCTest

@MainActor
final class NotificationPresentationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateRunningOctowatchIfNeeded()
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

    func testOfflineStartupShowsSingleRetryState() async throws {
        let app = launchFixture(named: "offline-startup")

        let offlineTitle = app.staticTexts["You're Offline"]
        XCTAssertTrue(offlineTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["GitHub Connection Required"].exists)
        XCTAssertFalse(app.buttons["Open Settings"].exists)
        XCTAssertTrue(app.buttons["Retry"].exists)
    }

    func testStartupWizardExplainsManualSetupWhenGitHubCLIMissing() async throws {
        let app = launchFixture(named: "auth-wizard-gh-missing")

        XCTAssertTrue(app.staticTexts["Connect GitHub"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["GitHub CLI was not found. Manual setup is required."]
                .exists
        )
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        XCTAssertTrue(app.buttons["GitHub Token Settings"].exists)
    }

    func testStartupWizardExplainsManualSetupWhenGitHubCLIFound() async throws {
        let app = launchFixture(named: "auth-wizard-gh-found")

        XCTAssertTrue(app.staticTexts["Connect GitHub"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["GitHub CLI was found, but Octowatch still needs manual setup."]
                .exists
        )
        XCTAssertTrue(app.buttons["Retry GitHub CLI"].exists)
        XCTAssertTrue(app.buttons["GitHub Token Settings"].exists)
    }

    func testFirstRunWizardShowsGitHubCLIContinuePath() async throws {
        let app = launchFixture(named: "first-run-gh-ready")

        XCTAssertTrue(app.staticTexts["Welcome to Octowatch"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["GitHub CLI was found and Octowatch will use it to authenticate."]
                .exists
        )
        XCTAssertTrue(app.buttons["Continue with GitHub CLI"].exists)
        XCTAssertTrue(app.buttons["Use Personal Access Token"].exists)

        app.buttons["Continue with GitHub CLI"].click()

        XCTAssertTrue(app.searchFields["Search inbox"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Welcome to Octowatch"].exists)
    }

    private func launchFixture(named fixtureName: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OCTOWATCH_UI_TEST_FIXTURE"] = fixtureName
        app.launch()
        return app
    }
}

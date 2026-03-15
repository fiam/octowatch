import XCTest

@MainActor
final class AutoMarkReadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMarkingVisibleItemUnreadWaitsForReselection() async throws {
        let app = XCUIApplication()
        app.launchEnvironment["OCTOWATCH_UI_TEST_FIXTURE"] = "auto-mark-read"
        app.launch()

        let inboxList = app.outlines["inbox-list"].firstMatch
        let primaryRow = app.staticTexts["sidebar-item-title-fixture-primary"]
        let secondaryRow = app.staticTexts["sidebar-item-title-fixture-secondary"]

        XCTAssertTrue(inboxList.waitForExistence(timeout: 5))
        XCTAssertTrue(primaryRow.waitForExistence(timeout: 5))
        XCTAssertTrue(secondaryRow.waitForExistence(timeout: 5))

        primaryRow.click()
        XCTAssertEqual(primaryRow.value as? String, "read")

        app.typeKey("u", modifierFlags: [.command, .shift])

        let rowBecomesUnread = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "unread"),
            object: primaryRow
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [rowBecomesUnread], timeout: 2),
            .completed
        )

        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(primaryRow.value as? String, "unread")

        secondaryRow.click()
        primaryRow.click()

        let rowBecomesRead = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "read"),
            object: primaryRow
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [rowBecomesRead], timeout: 2.5),
            .completed
        )
    }
}

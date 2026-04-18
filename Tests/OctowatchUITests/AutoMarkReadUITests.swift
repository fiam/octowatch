import XCTest

@MainActor
final class AutoMarkReadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateRunningOctowatchIfNeeded()
    }

    func testMarkingVisibleItemUnreadWaitsForReselection() async throws {
        let app = launchFixture(named: "auto-mark-read")
        let interruptionMonitor = addUIInterruptionMonitor(
            withDescription: "Foreground window interruption"
        ) { interruption in
            guard interruption.elementType == XCUIElement.ElementType.window else {
                return false
            }

            app.activate()
            return true
        }
        defer { removeUIInterruptionMonitor(interruptionMonitor) }

        let inboxList = app.outlines["inbox-list"].firstMatch
        let selectPrimaryButton = app.buttons["ui-test-select-primary"]
        let selectSecondaryButton = app.buttons["ui-test-select-secondary"]
        let testToggleReadStateButton = app.buttons["ui-test-toggle-read-state"]
        let autoMarkReadState = app.staticTexts["ui-test-auto-mark-read-state"]

        XCTAssertTrue(inboxList.waitForExistence(timeout: 5))
        XCTAssertTrue(selectPrimaryButton.waitForExistence(timeout: 5))
        XCTAssertTrue(selectSecondaryButton.waitForExistence(timeout: 5))
        XCTAssertTrue(testToggleReadStateButton.waitForExistence(timeout: 5))
        XCTAssertTrue(autoMarkReadState.waitForExistence(timeout: 5))

        activateAndClick(selectPrimaryButton, in: app)
        let primarySelectionIsVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@",
                "selected=https://github.com/example/octowatch/pull/1 unread=false suppressed=none toggles=0"
            ),
            object: autoMarkReadState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [primarySelectionIsVisible], timeout: 2),
            .completed
        )

        activateAndClick(testToggleReadStateButton, in: app)

        let toggleClickIsRecorded = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS %@",
                "toggles=1"
            ),
            object: autoMarkReadState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [toggleClickIsRecorded], timeout: 2),
            .completed
        )
        XCTAssertEqual(
            autoMarkReadState.label,
            "selected=https://github.com/example/octowatch/pull/1 unread=true suppressed=https://github.com/example/octowatch/pull/1 toggles=1",
            "unexpected state after toggle: \(autoMarkReadState.label)"
        )

        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(
            autoMarkReadState.label,
            "selected=https://github.com/example/octowatch/pull/1 unread=true suppressed=https://github.com/example/octowatch/pull/1 toggles=1"
        )

        activateAndClick(selectSecondaryButton, in: app)
        let secondarySelectionIsVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
                "selected=https://github.com/example/octowatch/pull/2",
                "suppressed=none",
                "toggles=1"
            ),
            object: autoMarkReadState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [secondarySelectionIsVisible], timeout: 2),
            .completed,
            "unexpected state after selecting secondary: \(autoMarkReadState.label)"
        )

        activateAndClick(selectPrimaryButton, in: app)

        let primarySelectionBecomesReadAgain = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@",
                "selected=https://github.com/example/octowatch/pull/1 unread=false suppressed=none toggles=1"
            ),
            object: autoMarkReadState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [primarySelectionBecomesReadAgain], timeout: 2.5),
            .completed
        )
    }
}

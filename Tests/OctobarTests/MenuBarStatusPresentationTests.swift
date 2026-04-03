import XCTest
@testable import Octowatch

final class MenuBarStatusPresentationTests: XCTestCase {
    func testUsesAlertPresentationForUnreadVisibleItems() {
        let presentation = MenuBarStatusPresentation(
            inboxSections: [
                InboxSectionPolicy.SectionResult(
                    name: "Your Turn",
                    items: [makeItem(id: "pr-1", isUnread: true)]
                )
            ]
        )

        XCTAssertEqual(presentation.imageName, "MenuBarIconAlert")
        XCTAssertEqual(presentation.fallbackSymbolName, "bell.badge.fill")
        XCTAssertEqual(presentation.toolTip, "1 unread item in your inbox.")
    }

    func testUsesDefaultPresentationWhenInboxIsEmpty() {
        let presentation = MenuBarStatusPresentation(inboxSections: [])

        XCTAssertEqual(presentation.imageName, "MenuBarIcon")
        XCTAssertEqual(presentation.fallbackSymbolName, "bell")
        XCTAssertEqual(presentation.toolTip, "Octowatch")
    }

    func testUsesDefaultPresentationForReadVisibleItems() {
        let presentation = MenuBarStatusPresentation(
            inboxSections: [
                InboxSectionPolicy.SectionResult(
                    name: "On Your Radar",
                    items: [
                        makeItem(id: "pr-1", isUnread: false),
                        makeItem(id: "pr-2", isUnread: false)
                    ]
                )
            ]
        )

        XCTAssertEqual(presentation.imageName, "MenuBarIcon")
        XCTAssertEqual(presentation.fallbackSymbolName, "bell")
        XCTAssertEqual(presentation.toolTip, "2 items in your inbox.")
    }

    func testPopoverSizingPolicyClampsHeightIntoAllowedRange() {
        XCTAssertEqual(
            MenuBarPopoverSizingPolicy.contentSize(
                width: 360,
                preferredHeight: 80,
                minHeight: 120,
                maxHeight: 520
            ),
            CGSize(width: 360, height: 120)
        )

        XCTAssertEqual(
            MenuBarPopoverSizingPolicy.contentSize(
                width: 360,
                preferredHeight: 640.2,
                minHeight: 120,
                maxHeight: 520
            ),
            CGSize(width: 360, height: 520)
        )
    }

    func testPopoverSizingPolicyFallsBackToMinimumHeightForInvalidValues() {
        XCTAssertEqual(
            MenuBarPopoverSizingPolicy.contentSize(
                width: 360,
                preferredHeight: 0,
                minHeight: 120,
                maxHeight: 520
            ),
            CGSize(width: 360, height: 120)
        )
    }

    private func makeItem(id: String, isUnread: Bool) -> AttentionItem {
        AttentionItem(
            id: id,
            subjectKey: "https://github.com/octowatch/octowatch/pull/\(id)",
            type: .reviewRequested,
            title: "Item \(id)",
            subtitle: "Needs review",
            timestamp: Date(timeIntervalSince1970: 1),
            url: URL(string: "https://github.com/octowatch/octowatch/pull/\(id)")!,
            isUnread: isUnread
        )
    }
}

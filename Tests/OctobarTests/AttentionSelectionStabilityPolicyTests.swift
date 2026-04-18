import XCTest
@testable import Octowatch

final class AttentionSelectionStabilityPolicyTests: XCTestCase {
    func testKeepsRequestedSelectionWhenItIsVisible() {
        XCTAssertEqual(
            AttentionSelectionStabilityPolicy.stabilizing(
                requestedSelection: ["fixture-secondary"],
                currentSelection: ["fixture-primary"],
                displayedItemIDs: ["fixture-primary", "fixture-secondary"]
            ),
            ["fixture-secondary"]
        )
    }

    func testRetainsCurrentSelectionWhenListTransientlyClearsIt() {
        XCTAssertEqual(
            AttentionSelectionStabilityPolicy.stabilizing(
                requestedSelection: [],
                currentSelection: ["fixture-primary"],
                displayedItemIDs: ["fixture-primary", "fixture-secondary"]
            ),
            ["fixture-primary"]
        )
    }

    func testAllowsEmptySelectionWhenCurrentItemIsGone() {
        XCTAssertEqual(
            AttentionSelectionStabilityPolicy.stabilizing(
                requestedSelection: [],
                currentSelection: ["fixture-primary"],
                displayedItemIDs: ["fixture-secondary"]
            ),
            []
        )
    }

    func testRemapsSelectionUsingRememberedSubjectKeyWhenIDsChange() {
        let items = [
            AttentionItem(
                id: "https://github.com/example/octowatch/pull/1",
                subjectKey: "https://github.com/example/octowatch/pull/1",
                type: .reviewRequested,
                title: "Primary fixture item",
                subtitle: "example/octowatch",
                timestamp: .now,
                url: URL(string: "https://github.com/example/octowatch/pull/1")!,
                isUnread: true
            ),
            AttentionItem(
                id: "https://github.com/example/octowatch/pull/2",
                subjectKey: "https://github.com/example/octowatch/pull/2",
                type: .comment,
                title: "Secondary fixture item",
                subtitle: "example/octowatch",
                timestamp: .now,
                url: URL(string: "https://github.com/example/octowatch/pull/2")!,
                isUnread: true
            )
        ]

        XCTAssertEqual(
            AttentionSelectionStabilityPolicy.stabilizing(
                requestedSelection: ["fixture-primary"],
                currentSelection: ["fixture-primary"],
                rememberedSubjectKeys: ["https://github.com/example/octowatch/pull/1"],
                displayedItems: items
            ),
            ["https://github.com/example/octowatch/pull/1"]
        )
    }

    func testDoesNotRemapSelectionWhenRememberedSubjectKeyIsMissing() {
        let items = [
            AttentionItem(
                id: "https://github.com/example/octowatch/pull/2",
                subjectKey: "https://github.com/example/octowatch/pull/2",
                type: .comment,
                title: "Secondary fixture item",
                subtitle: "example/octowatch",
                timestamp: .now,
                url: URL(string: "https://github.com/example/octowatch/pull/2")!,
                isUnread: true
            )
        ]

        XCTAssertEqual(
            AttentionSelectionStabilityPolicy.stabilizing(
                requestedSelection: ["fixture-primary"],
                currentSelection: ["fixture-primary"],
                rememberedSubjectKeys: ["https://github.com/example/octowatch/pull/1"],
                displayedItems: items
            ),
            []
        )
    }

    func testRetainsRememberedSubjectKeyWhenSelectionMomentarilyClears() {
        let items = [
            AttentionItem(
                id: "https://github.com/example/octowatch/pull/1",
                subjectKey: "https://github.com/example/octowatch/pull/1",
                type: .reviewRequested,
                title: "Primary fixture item",
                subtitle: "example/octowatch",
                timestamp: .now,
                url: URL(string: "https://github.com/example/octowatch/pull/1")!,
                isUnread: true
            ),
            AttentionItem(
                id: "https://github.com/example/octowatch/pull/2",
                subjectKey: "https://github.com/example/octowatch/pull/2",
                type: .comment,
                title: "Secondary fixture item",
                subtitle: "example/octowatch",
                timestamp: .now,
                url: URL(string: "https://github.com/example/octowatch/pull/2")!,
                isUnread: true
            )
        ]

        XCTAssertEqual(
            AttentionSelectionStabilityPolicy.retainingRememberedSubjectKeys(
                from: ["https://github.com/example/octowatch/pull/1"],
                selection: [],
                displayedItems: items
            ),
            ["https://github.com/example/octowatch/pull/1"]
        )
    }

    func testPrefersRememberedSubjectForAutoSelection() {
        let items = [
            AttentionItem(
                id: "https://github.com/example/octowatch/pull/2",
                subjectKey: "https://github.com/example/octowatch/pull/2",
                type: .comment,
                title: "Secondary fixture item",
                subtitle: "example/octowatch",
                timestamp: .now,
                url: URL(string: "https://github.com/example/octowatch/pull/2")!,
                isUnread: true
            ),
            AttentionItem(
                id: "https://github.com/example/octowatch/pull/1",
                subjectKey: "https://github.com/example/octowatch/pull/1",
                type: .reviewRequested,
                title: "Primary fixture item",
                subtitle: "example/octowatch",
                timestamp: .now,
                url: URL(string: "https://github.com/example/octowatch/pull/1")!,
                isUnread: true
            )
        ]

        XCTAssertEqual(
            AttentionSelectionStabilityPolicy.preferredAutoSelectionItemID(
                rememberedSubjectKeys: ["https://github.com/example/octowatch/pull/1"],
                displayedItems: items
            ),
            "https://github.com/example/octowatch/pull/1"
        )
    }
}

import XCTest
@testable import Octowatch

final class AttentionClassificationTests: XCTestCase {
    func testCommentReasonsMapToCommentAttention() {
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "comment",
                timelineEvent: nil,
                reviewState: nil
            ),
            .comment
        )
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "subscribed",
                timelineEvent: nil,
                reviewState: nil
            ),
            .comment
        )
    }

    func testTimelineReviewStateOverridesReason() {
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "author",
                timelineEvent: "reviewed",
                reviewState: "APPROVED"
            ),
            .reviewApproved
        )
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "author",
                timelineEvent: "reviewed",
                reviewState: "CHANGES_REQUESTED"
            ),
            .reviewChangesRequested
        )
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "author",
                timelineEvent: "reviewed",
                reviewState: "COMMENTED"
            ),
            .reviewComment
        )
    }

    func testWorkflowAttentionClassification() {
        XCTAssertEqual(
            AttentionItemType.workflowType(status: "action_required", conclusion: nil),
            .workflowApprovalRequired
        )
        XCTAssertEqual(
            AttentionItemType.workflowType(status: "completed", conclusion: "failure"),
            .workflowFailed
        )
        XCTAssertNil(
            AttentionItemType.workflowType(status: "completed", conclusion: "success")
        )
    }

    func testRecentlyClosedPullRequestsStillCountForDiscussionActivity() {
        let recentClosure = Date().addingTimeInterval(-43_200)
        let staleClosure = Date().addingTimeInterval(-172_800)

        XCTAssertTrue(
            PullRequestAttentionPolicy.shouldIncludeActivity(
                state: "closed",
                merged: true,
                closedAt: recentClosure,
                now: Date()
            )
        )
        XCTAssertFalse(
            PullRequestAttentionPolicy.shouldIncludeActivity(
                state: "closed",
                merged: true,
                closedAt: staleClosure,
                now: Date()
            )
        )
    }

    func testWorkflowWatchPolicyKeepsOpenAndRecentMergedPullRequests() {
        XCTAssertTrue(
            PullRequestAttentionPolicy.shouldWatchWorkflows(
                state: "open",
                merged: false,
                mergedAt: nil,
                now: Date()
            )
        )
        XCTAssertTrue(
            PullRequestAttentionPolicy.shouldWatchWorkflows(
                state: "closed",
                merged: true,
                mergedAt: Date().addingTimeInterval(-3_600),
                now: Date()
            )
        )
        XCTAssertFalse(
            PullRequestAttentionPolicy.shouldWatchWorkflows(
                state: "closed",
                merged: true,
                mergedAt: Date().addingTimeInterval(-172_800),
                now: Date()
            )
        )
    }
}

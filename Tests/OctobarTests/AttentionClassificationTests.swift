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

    func testTeamScopedNotificationReasonsMapToDistinctAttention() {
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "team_mention",
                timelineEvent: nil,
                reviewState: nil
            ),
            .teamMention
        )
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "review_requested",
                timelineEvent: nil,
                reviewState: nil,
                teamScoped: true
            ),
            .teamReviewRequested
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

    func testIgnoringSubjectRemovesAllMatchingAttentionItems() {
        let ignoredKey = "https://github.com/acme/example/pull/42"
        let keptKey = "https://github.com/acme/example/pull/43"
        let now = Date()

        let ignoredPullRequest = AttentionItem(
            id: "pr:1",
            ignoreKey: ignoredKey,
            type: .assignedPullRequest,
            title: "Ignored PR",
            subtitle: "#42 · acme/example",
            timestamp: now,
            url: URL(string: "https://github.com/acme/example/pull/42")!
        )
        let ignoredWorkflow = AttentionItem(
            id: "run:1",
            ignoreKey: ignoredKey,
            type: .workflowFailed,
            title: "Ignored workflow",
            subtitle: "acme/example · PR #42 · Workflow failed",
            timestamp: now,
            url: URL(string: "https://github.com/acme/example/actions/runs/1")!
        )
        let keptPullRequest = AttentionItem(
            id: "pr:2",
            ignoreKey: keptKey,
            type: .assignedPullRequest,
            title: "Kept PR",
            subtitle: "#43 · acme/example",
            timestamp: now,
            url: URL(string: "https://github.com/acme/example/pull/43")!
        )

        let filtered = AttentionItemVisibilityPolicy.excludingIgnoredSubjects(
            [ignoredPullRequest, ignoredWorkflow, keptPullRequest],
            ignoredKeys: [ignoredKey]
        )

        XCTAssertEqual(filtered, [keptPullRequest])
    }

    func testLegacyIgnoreKeyPlaceholderMigratesToCanonicalURL() {
        let placeholder = IgnoredAttentionSubject.placeholder(for: "pr:acme/example#42")

        XCTAssertEqual(
            placeholder.ignoreKey,
            "https://github.com/acme/example/pull/42"
        )
        XCTAssertEqual(placeholder.title, "Pull Request #42")
        XCTAssertEqual(placeholder.subtitle, "acme/example")
    }

    func testRateLimitUsesGitHubPollHintWhenHigherThanConfiguredInterval() {
        let rateLimit = GitHubRateLimit(
            limit: 5_000,
            remaining: 4_200,
            resetAt: Date().addingTimeInterval(3_600),
            pollIntervalHintSeconds: 120,
            retryAfterSeconds: nil
        )

        XCTAssertEqual(
            rateLimit.minimumAutomaticRefreshInterval(userConfiguredSeconds: 60, now: Date()),
            120
        )
    }

    func testRateLimitBacksOffWhenBudgetIsLow() {
        let rateLimit = GitHubRateLimit(
            limit: 5_000,
            remaining: 18,
            resetAt: Date().addingTimeInterval(3_600),
            pollIntervalHintSeconds: nil,
            retryAfterSeconds: nil
        )

        XCTAssertEqual(
            rateLimit.minimumAutomaticRefreshInterval(userConfiguredSeconds: 60, now: Date()),
            900
        )
    }

    func testRateLimitWaitsUntilResetWhenExhausted() {
        let now = Date()
        let rateLimit = GitHubRateLimit(
            limit: 5_000,
            remaining: 0,
            resetAt: now.addingTimeInterval(420),
            pollIntervalHintSeconds: 60,
            retryAfterSeconds: nil
        )

        XCTAssertEqual(
            rateLimit.minimumAutomaticRefreshInterval(userConfiguredSeconds: 30, now: now),
            420
        )
    }

    func testAutoMarkReadSettingMapsToExpectedDelay() {
        XCTAssertNil(AutoMarkReadSetting.never.delay)
        XCTAssertEqual(AutoMarkReadSetting.oneSecond.delay, .seconds(1))
        XCTAssertEqual(AutoMarkReadSetting.threeSeconds.delay, .seconds(3))
        XCTAssertEqual(AutoMarkReadSetting.fiveSeconds.delay, .seconds(5))
        XCTAssertEqual(AutoMarkReadSetting.tenSeconds.delay, .seconds(10))
        XCTAssertEqual(AutoMarkReadSetting.normalized(rawValue: 999), .threeSeconds)
    }
}

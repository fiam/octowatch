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
    }

    func testLowSignalNotificationReasonsAreNotActionable() {
        XCTAssertFalse(NotificationAttentionPolicy.isActionable(reason: "subscribed"))
        XCTAssertFalse(NotificationAttentionPolicy.isActionable(reason: "manual"))
        XCTAssertTrue(NotificationAttentionPolicy.isActionable(reason: "comment"))
    }

    func testFallbackNotificationPolicyDropsStaleDiscussionThreads() {
        let now = Date()

        XCTAssertTrue(
            NotificationAttentionPolicy.shouldIncludeFallback(
                reason: "comment",
                updatedAt: now.addingTimeInterval(-3_600),
                now: now
            )
        )
        XCTAssertEqual(
            NotificationAttentionPolicy.shouldIncludeFallback(
                reason: "comment",
                updatedAt: now.addingTimeInterval(-172_800),
                now: now
            ),
            false
        )
        XCTAssertTrue(
            NotificationAttentionPolicy.shouldIncludeFallback(
                reason: "mention",
                updatedAt: now.addingTimeInterval(-172_800),
                now: now
            )
        )
    }

    func testFallbackPolicyOnlyKeepsOpenPullRequests() {
        XCTAssertTrue(
            NotificationAttentionPolicy.shouldIncludePullRequestFallback(
                state: "open",
                merged: false
            )
        )
        XCTAssertFalse(
            NotificationAttentionPolicy.shouldIncludePullRequestFallback(
                state: "closed",
                merged: false
            )
        )
        XCTAssertFalse(
            NotificationAttentionPolicy.shouldIncludePullRequestFallback(
                state: "closed",
                merged: true
            )
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

    func testCommitFollowUpOverridesGenericStateChange() {
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "comment",
                timelineEvent: "committed",
                reviewState: nil,
                followUpRelationship: .afterYourComment
            ),
            .newCommitsAfterComment
        )
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "comment",
                timelineEvent: "head_ref_force_pushed",
                reviewState: nil,
                followUpRelationship: .afterYourReview
            ),
            .newCommitsAfterReview
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

    func testSmallBucketRateLimitDoesNotForceFifteenMinuteBackoff() {
        let now = Date()
        let rateLimit = GitHubRateLimit(
            limit: 30,
            remaining: 20,
            resetAt: now.addingTimeInterval(40),
            pollIntervalHintSeconds: nil,
            retryAfterSeconds: nil
        )

        XCTAssertEqual(
            rateLimit.minimumAutomaticRefreshInterval(userConfiguredSeconds: 60, now: now),
            60
        )
    }

    func testSmallBucketRateLimitWaitsForResetOnlyWhenNearlyExhausted() {
        let now = Date()
        let rateLimit = GitHubRateLimit(
            limit: 30,
            remaining: 5,
            resetAt: now.addingTimeInterval(45),
            pollIntervalHintSeconds: nil,
            retryAfterSeconds: nil
        )

        XCTAssertEqual(
            rateLimit.minimumAutomaticRefreshInterval(userConfiguredSeconds: 30, now: now),
            45
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

    func testNotificationScanStateNormalizesDepthAndDeduplicatesThreadIDs() {
        let normalized = NotificationScanState(
            knownActionableThreadIDs: ["a", "b", "a"],
            preferredPageDepth: 99
        ).normalized

        XCTAssertEqual(normalized.knownActionableThreadIDs, ["a", "b"])
        XCTAssertEqual(normalized.preferredPageDepth, 10)
    }

    func testTeamMembershipCacheNormalizesAndMatchesOwnerSlugKeys() {
        let cache = TeamMembershipCache(
            membershipKeys: ["Acme/BuildOps", "acme/buildops", "ExampleOrg/Developers"],
            fetchedAt: nil,
            lastAttemptAt: nil
        ).normalized

        XCTAssertEqual(
            cache.membershipKeys,
            ["acme/buildops", "exampleorg/developers"]
        )
        XCTAssertTrue(cache.contains(owner: "acme", slug: "buildops"))
        XCTAssertTrue(cache.contains(owner: "ExampleOrg", slug: "developers"))
        XCTAssertFalse(cache.contains(owner: "acme", slug: "iam-team"))
    }

    func testTeamMembershipCacheFreshnessUsesLastAttempt() {
        let now = Date()

        XCTAssertTrue(
            TeamMembershipCache.default
                .recordingAttempt(at: now.addingTimeInterval(-3_600))
                .isFresh(relativeTo: now)
        )
        XCTAssertFalse(
            TeamMembershipCache.default
                .recordingAttempt(at: now.addingTimeInterval(-172_800))
                .isFresh(relativeTo: now)
        )
    }

    func testReadyToMergePolicyRequiresCleanOpenApprovedPullRequest() {
        XCTAssertTrue(
            AuthoredPullRequestAttentionPolicy.shouldSurfaceReadyToMerge(
                state: "open",
                merged: false,
                isDraft: false,
                mergeable: true,
                mergeableState: "clean",
                pendingReviewRequests: 0,
                approvalCount: 1,
                hasChangesRequested: false
            )
        )
        XCTAssertFalse(
            AuthoredPullRequestAttentionPolicy.shouldSurfaceReadyToMerge(
                state: "open",
                merged: false,
                isDraft: false,
                mergeable: true,
                mergeableState: "dirty",
                pendingReviewRequests: 0,
                approvalCount: 1,
                hasChangesRequested: false
            )
        )
        XCTAssertFalse(
            AuthoredPullRequestAttentionPolicy.shouldSurfaceReadyToMerge(
                state: "open",
                merged: false,
                isDraft: false,
                mergeable: true,
                mergeableState: "clean",
                pendingReviewRequests: 1,
                approvalCount: 1,
                hasChangesRequested: false
            )
        )
    }

    func testAssignedPullRequestDoesNotDuplicateHeaderStateWithBadges() {
        let badges = PullRequestContextBadge.badges(
            for: .assignedPullRequest,
            author: AttentionActor(
                login: "renovate-custom-app",
                avatarURL: nil,
                isBot: true
            )
        )

        XCTAssertTrue(badges.isEmpty)
    }

    func testTeamReviewRequestedDoesNotDuplicateHeaderStateWithBadges() {
        let badges = PullRequestContextBadge.badges(
            for: .teamReviewRequested,
            author: AttentionActor(
                login: "dependabot[bot]",
                avatarURL: nil,
                isBot: true
            )
        )

        XCTAssertTrue(badges.isEmpty)
    }

    func testReadyToMergeDoesNotAddSeparateCreatedByYouBadge() {
        let badges = PullRequestContextBadge.badges(
            for: .readyToMerge,
            author: AttentionActor(
                login: "alberto",
                avatarURL: nil,
                isBot: false
            )
        )

        XCTAssertTrue(badges.isEmpty)
    }

    func testReadyToMergeHeaderFactsUseApprovalLanguage() {
        let facts = PullRequestHeaderFact.build(
            sourceType: .readyToMerge,
            author: nil,
            assigner: nil,
            latestApprover: AttentionActor(login: "nicksieger", avatarURL: nil, isBot: false),
            approvalCount: 3
        )

        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.label, "approved by")
        XCTAssertEqual(facts.first?.overflowLabel, "and 2 more people")
    }

    func testAssignedPullRequestHeaderFactsIncludeAuthorAndAssigner() {
        let facts = PullRequestHeaderFact.build(
            sourceType: .assignedPullRequest,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            assigner: AttentionActor(login: "fiam", avatarURL: nil, isBot: false),
            latestApprover: nil,
            approvalCount: 0
        )

        XCTAssertEqual(facts.map(\.label), ["created by", "assigned by"])
        XCTAssertEqual(facts.map(\.actor.login), ["renovate-custom-app", "fiam"])
    }

    func testAuthoredPullRequestActionsIncludeMergeAndView() {
        let actions = AttentionAction.pullRequestActions(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 639),
            sourceType: .readyToMerge,
            mode: .authored,
            reviewDecision: "APPROVED",
            mergeable: "MERGEABLE",
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            hasNewCommits: false
        )

        XCTAssertEqual(actions.map(\.id), ["merge", "view-pr", "open-files", "open-checks"])
        XCTAssertEqual(actions.first?.isPrimary, true)
        XCTAssertEqual(actions.dropFirst().first?.isPrimary, false)
    }

    func testAssignedPullRequestActionsUseViewAsPrimary() {
        let actions = AttentionAction.pullRequestActions(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 638),
            sourceType: .assignedPullRequest,
            mode: .generic,
            reviewDecision: nil,
            mergeable: nil,
            checkSummary: .empty,
            hasNewCommits: false
        )

        XCTAssertEqual(actions.map(\.id), ["view-pr", "open-files"])
        XCTAssertEqual(actions.first?.title, "View on GitHub")
        XCTAssertEqual(actions.first?.isPrimary, true)
    }

    func testBotAssignedReviewMergeActionEnablesApproveAndMergeWhenClean() {
        let action = PullRequestReviewMergeAction.makeBotAssignedAction(
            sourceType: .assignedPullRequest,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            checkSummary: PullRequestCheckSummary(
                passedCount: 12,
                skippedCount: 2,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.title, "Approve and Merge")
        XCTAssertEqual(action?.requiresApproval, true)
        XCTAssertEqual(action?.isEnabled, true)
        XCTAssertNil(action?.disabledReason)
    }

    func testBotAssignedReviewMergeActionDisablesOnFailures() {
        let action = PullRequestReviewMergeAction.makeBotAssignedAction(
            sourceType: .assignedPullRequest,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 3,
                failedCount: 2,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(action?.disabledReason, "Some checks are failing.")
    }

    func testPullRequestStatusSummaryShowsReadyToApproveAndMerge() {
        let action = PullRequestReviewMergeAction.makeBotAssignedAction(
            sourceType: .assignedPullRequest,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            checkSummary: PullRequestCheckSummary(
                passedCount: 12,
                skippedCount: 2,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        let summary = PullRequestStatusSummary.build(
            mode: .generic,
            checkSummary: PullRequestCheckSummary(
                passedCount: 12,
                skippedCount: 2,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            reviewMergeAction: action
        )

        XCTAssertEqual(summary?.title, "Ready to approve and merge")
        XCTAssertEqual(summary?.detail, "12 passed · 2 skipped")
        XCTAssertEqual(summary?.accent, .success)
    }

    func testPullRequestStatusSummaryShowsFailedChecks() {
        let summary = PullRequestStatusSummary.build(
            mode: .generic,
            checkSummary: PullRequestCheckSummary(
                passedCount: 9,
                skippedCount: 3,
                failedCount: 2,
                pendingCount: 0
            ),
            openThreadCount: 0,
            reviewMergeAction: nil
        )

        XCTAssertEqual(summary?.title, "2 checks failed")
        XCTAssertEqual(summary?.detail, "2 failed · 9 passed · 3 skipped")
        XCTAssertEqual(summary?.accent, .failure)
    }

    func testAttentionItemParsesPullRequestReferenceFromCanonicalURL() {
        let item = AttentionItem(
            id: "pr:1",
            ignoreKey: "https://github.com/acme/example/pull/42",
            type: .assignedPullRequest,
            title: "Example",
            subtitle: "acme/example · Review requested",
            repository: "acme/example",
            timestamp: Date(),
            url: URL(string: "https://github.com/acme/example/pull/42")!
        )

        XCTAssertEqual(
            item.pullRequestReference,
            PullRequestReference(owner: "acme", name: "example", number: 42)
        )
    }

    func testAttentionItemDoesNotParseIssueAsPullRequestReference() {
        let item = AttentionItem(
            id: "issue:1",
            ignoreKey: "https://github.com/acme/example/issues/42",
            type: .mention,
            title: "Example issue",
            subtitle: "acme/example · Mentioned you",
            repository: "acme/example",
            timestamp: Date(),
            url: URL(string: "https://github.com/acme/example/issues/42")!
        )

        XCTAssertNil(item.pullRequestReference)
    }
}

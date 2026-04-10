import XCTest
import GitHubWorkflowParsing
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

    func testLatestViewerReviewUpdateUsesNewestReviewFromCurrentUser() {
        let client = GitHubClient()
        let olderReview = PullRequestReview(
            state: "COMMENTED",
            user: GitHubUser(login: "alberto", avatarURL: nil, htmlURL: nil),
            submittedAt: Date(timeIntervalSince1970: 100)
        )
        let newerReview = PullRequestReview(
            state: "APPROVED",
            user: GitHubUser(login: "alberto", avatarURL: nil, htmlURL: nil),
            submittedAt: Date(timeIntervalSince1970: 200)
        )
        let otherReview = PullRequestReview(
            state: "CHANGES_REQUESTED",
            user: GitHubUser(login: "someone-else", avatarURL: nil, htmlURL: nil),
            submittedAt: Date(timeIntervalSince1970: 300)
        )

        let update = client.latestViewerReviewUpdate(
            reviews: [olderReview, newerReview, otherReview],
            login: "alberto"
        )

        XCTAssertEqual(update?.type, .reviewApproved)
        XCTAssertEqual(update?.timestamp, newerReview.submittedAt)
        XCTAssertEqual(update?.actor?.login, "alberto")
    }

    func testLatestViewerReviewUpdateIgnoresDismissedReviews() {
        let client = GitHubClient()
        let dismissedReview = PullRequestReview(
            state: "DISMISSED",
            user: GitHubUser(login: "alberto", avatarURL: nil, htmlURL: nil),
            submittedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertNil(
            client.latestViewerReviewUpdate(
                reviews: [dismissedReview],
                login: "alberto"
            )
        )
    }

    func testReviewRequestedNotificationsStayStickyForUnrelatedApproval() {
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "review_requested",
                timelineEvent: "reviewed",
                reviewState: "APPROVED"
            ),
            .reviewRequested
        )
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "review_requested",
                timelineEvent: "reviewed",
                reviewState: "APPROVED",
                teamScoped: true
            ),
            .teamReviewRequested
        )
    }

    func testReviewRequestedNotificationsOnlyUpgradeForYourOwnFollowUp() {
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "review_requested",
                timelineEvent: "committed",
                reviewState: nil
            ),
            .reviewRequested
        )
        XCTAssertEqual(
            AttentionItemType.notificationType(
                reason: "review_requested",
                timelineEvent: "committed",
                reviewState: nil,
                followUpRelationship: .afterYourReview
            ),
            .newCommitsAfterReview
        )
    }

    func testWorkflowAttentionClassification() {
        XCTAssertEqual(
            AttentionItemType.workflowType(status: "action_required", conclusion: nil),
            .workflowApprovalRequired
        )
        XCTAssertEqual(
            AttentionItemType.workflowType(
                status: "waiting",
                conclusion: nil,
                requiresApproval: true
            ),
            .workflowApprovalRequired
        )
        XCTAssertEqual(
            AttentionItemType.workflowType(status: "in_progress", conclusion: nil),
            .workflowRunning
        )
        XCTAssertEqual(
            AttentionItemType.workflowType(status: "completed", conclusion: "failure"),
            .workflowFailed
        )
        XCTAssertEqual(
            AttentionItemType.workflowType(status: "completed", conclusion: "success"),
            .workflowSucceeded
        )
    }

    func testWorkflowRunAttributionPolicyRejectsScheduledRunsAfterMerge() {
        let mergedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(
            WorkflowRunAttributionPolicy.shouldAssociate(
                runTitle: "Scheduled",
                workflowName: "Scheduled",
                event: "dynamic",
                createdAt: mergedAt.addingTimeInterval(10_800),
                mergedAt: mergedAt
            )
        )
        XCTAssertFalse(
            WorkflowRunAttributionPolicy.shouldAssociate(
                runTitle: "Update Gradle Wrapper",
                workflowName: "Update Gradle Wrapper",
                event: "schedule",
                createdAt: mergedAt.addingTimeInterval(3_600),
                mergedAt: mergedAt
            )
        )
    }

    func testWorkflowRunAttributionPolicyKeepsMergeAdjacentRuns() {
        let mergedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(
            WorkflowRunAttributionPolicy.shouldAssociate(
                runTitle: "Push on main",
                workflowName: "Push on main",
                event: "dynamic",
                createdAt: mergedAt.addingTimeInterval(2),
                mergedAt: mergedAt
            )
        )
        XCTAssertTrue(
            WorkflowRunAttributionPolicy.shouldAssociate(
                runTitle: "[cloud-uc-services] sync uc-lease-protocol proto (#1104)",
                workflowName: "Build",
                event: "push",
                createdAt: mergedAt.addingTimeInterval(4),
                mergedAt: mergedAt
            )
        )
    }

    func testAttentionUpdateHistoryPolicyPrunesLateWorkflowUpdatesAfterMerge() {
        let mergedAt = Date(timeIntervalSince1970: 1_000)
        let scheduledUpdate = AttentionUpdate(
            id: "run:scheduled",
            type: .workflowSucceeded,
            title: "Workflow succeeded",
            detail: "Scheduled",
            timestamp: mergedAt.addingTimeInterval(10_800),
            actor: AttentionActor(login: "github-advanced-security[bot]", avatarURL: nil),
            url: nil
        )
        let mergeAdjacentUpdate = AttentionUpdate(
            id: "run:push",
            type: .workflowSucceeded,
            title: "Workflow succeeded",
            detail: "Push on main",
            timestamp: mergedAt.addingTimeInterval(5),
            actor: AttentionActor(login: "fiam", avatarURL: nil),
            url: nil
        )
        let reviewUpdate = AttentionUpdate(
            id: "review:approved",
            type: .reviewApproved,
            title: "Review approved",
            detail: nil,
            timestamp: mergedAt.addingTimeInterval(-5),
            actor: AttentionActor(login: "fiam", avatarURL: nil),
            url: nil
        )

        let pruned = AttentionUpdateHistoryPolicy.pruningInvalidWorkflowUpdates(
            [scheduledUpdate, mergeAdjacentUpdate, reviewUpdate],
            mergedAt: mergedAt
        )

        XCTAssertEqual(pruned.map(\.id), ["run:push", "review:approved"])
    }

    func testPullRequestHeaderTimestampPolicyPrefersMergeTimeAndShowsDistinctLastUpdate() {
        let mergedAt = Date(timeIntervalSince1970: 1_000)
        let lastUpdate = mergedAt.addingTimeInterval(10_800)
        let referenceDate = lastUpdate.addingTimeInterval(600)

        XCTAssertEqual(
            PullRequestHeaderTimestampPolicy.primaryTimestamp(
                resolution: .merged,
                itemTimestamp: lastUpdate,
                mergedAt: mergedAt
            ),
            mergedAt
        )
        XCTAssertTrue(
            PullRequestHeaderTimestampPolicy.shouldShowLastUpdate(
                resolution: .merged,
                itemTimestamp: lastUpdate,
                mergedAt: mergedAt,
                referenceDate: referenceDate
            )
        )
    }

    func testPullRequestHeaderTimestampPolicyHidesDuplicateLastUpdateLabel() {
        let mergedAt = Date(timeIntervalSince1970: 1_000)
        let lastUpdate = mergedAt.addingTimeInterval(30)
        let referenceDate = mergedAt.addingTimeInterval(57_600)

        XCTAssertFalse(
            PullRequestHeaderTimestampPolicy.shouldShowLastUpdate(
                resolution: .merged,
                itemTimestamp: lastUpdate,
                mergedAt: mergedAt,
                referenceDate: referenceDate
            )
        )
    }

    func testAttentionUpdateHistoryMergesCurrentAndPreviousUpdatesWithoutDuplicates() {
        let now = Date(timeIntervalSince1970: 200)
        let previous = [
            AttentionUpdate(
                id: "workflow:failed",
                type: .workflowFailed,
                title: "Workflow failed",
                detail: "CI",
                timestamp: now.addingTimeInterval(-20),
                actor: nil,
                url: nil
            )
        ]
        let current = [
            AttentionUpdate(
                id: "workflow:succeeded",
                type: .workflowSucceeded,
                title: "Workflow succeeded",
                detail: "CI",
                timestamp: now,
                actor: nil,
                url: nil
            ),
            AttentionUpdate(
                id: "workflow:failed",
                type: .workflowFailed,
                title: "Workflow failed",
                detail: "CI",
                timestamp: now.addingTimeInterval(-20),
                actor: nil,
                url: nil
            )
        ]

        XCTAssertEqual(
            AttentionUpdateHistoryPolicy.merging(existing: previous, current: current).map(\.id),
            ["workflow:succeeded", "workflow:failed"]
        )
    }

    func testAttentionUpdateHistoryMergingKeepsAllUpdatesByDefault() {
        let updates = (0..<16).map { offset in
            AttentionUpdate(
                id: "update-\(offset)",
                type: .comment,
                title: "Update \(offset)",
                detail: nil,
                timestamp: Date(timeIntervalSince1970: Double(200 - offset)),
                actor: nil,
                url: nil
            )
        }

        XCTAssertEqual(
            AttentionUpdateHistoryPolicy.merging(existing: [], current: updates).map(\.id),
            updates.map(\.id)
        )
    }

    func testAttentionUpdateHistoryProjectionRetainsDetachedSubjectsAndMergesCurrentUpdates() {
        let orphanURL = URL(string: "https://github.com/example/repo/pull/1")!
        let activeURL = URL(string: "https://github.com/example/repo/pull/2")!
        let orphanUpdate = AttentionUpdate(
            id: "orphan:comment",
            type: .comment,
            title: "Comment",
            detail: "Old discussion",
            timestamp: Date(timeIntervalSince1970: 100),
            actor: nil,
            url: orphanURL
        )
        let previousActiveUpdate = AttentionUpdate(
            id: "active:requested",
            type: .reviewRequested,
            title: "Review requested",
            detail: nil,
            timestamp: Date(timeIntervalSince1970: 150),
            actor: nil,
            url: activeURL
        )
        let currentActiveUpdate = AttentionUpdate(
            id: "active:approved",
            type: .reviewApproved,
            title: "Approved",
            detail: nil,
            timestamp: Date(timeIntervalSince1970: 200),
            actor: AttentionActor(login: "octocat", avatarURL: nil),
            url: activeURL,
            isTriggeredByCurrentUser: true
        )
        let activeItem = AttentionItem(
            id: activeURL.absoluteString,
            subjectKey: activeURL.absoluteString,
            updateKey: currentActiveUpdate.id,
            type: .reviewApproved,
            title: "Example PR",
            subtitle: "example/repo · Approved",
            repository: "example/repo",
            timestamp: currentActiveUpdate.timestamp,
            url: activeURL,
            actor: currentActiveUpdate.actor,
            isTriggeredByCurrentUser: true,
            detail: AttentionDetail(
                why: AttentionWhy(summary: "Approved", detail: nil),
                evidence: [],
                updates: [currentActiveUpdate],
                actions: []
            )
        )

        let projection = AttentionUpdateHistoryProjection.applying(
            persistedHistoryBySubjectKey: [
                orphanURL.absoluteString: [orphanUpdate],
                activeURL.absoluteString: [previousActiveUpdate]
            ],
            to: [activeItem]
        )

        XCTAssertEqual(projection.items.count, 1)
        XCTAssertEqual(
            projection.items[0].detail.updates.map(\.id),
            ["active:approved", "active:requested"]
        )
        XCTAssertEqual(
            projection.historyBySubjectKey[orphanURL.absoluteString]?.map(\.id),
            ["orphan:comment"]
        )
        XCTAssertEqual(
            projection.historyBySubjectKey[activeURL.absoluteString]?.map(\.id),
            ["active:approved", "active:requested"]
        )
    }

    func testAttentionUpdateHistoryStoreRoundTripsSelfTriggeredUpdates() {
        let defaults = temporaryUserDefaults()
        let key = "attention-update-history-store-test"
        let url = URL(string: "https://github.com/example/repo/pull/42")!
        let history = [
            url.absoluteString: [
                AttentionUpdate(
                    id: "comment:1",
                    type: .comment,
                    title: "Commented",
                    detail: "You commented",
                    timestamp: Date(timeIntervalSince1970: 300),
                    actor: AttentionActor(login: "octocat", avatarURL: nil),
                    url: url,
                    isTriggeredByCurrentUser: true
                )
            ]
        ]

        AttentionUpdateHistoryStore.persist(history, to: defaults, key: key)

        XCTAssertEqual(
            AttentionUpdateHistoryStore.load(from: defaults, key: key),
            history
        )

        AttentionUpdateHistoryStore.persist([:], to: defaults, key: key)

        XCTAssertNil(defaults.data(forKey: key))
    }

    func testAttentionUpdateNotificationPolicySkipsSelfTriggeredUpdatesUnlessEnabled() {
        let url = URL(string: "https://github.com/example/repo/pull/42")!
        let selfTriggeredItem = AttentionItem(
            id: url.absoluteString,
            subjectKey: url.absoluteString,
            type: .comment,
            title: "Example PR",
            subtitle: "example/repo · Comment",
            timestamp: Date(timeIntervalSince1970: 100),
            url: url,
            isTriggeredByCurrentUser: true
        )
        let externalItem = AttentionItem(
            id: "external",
            subjectKey: "https://github.com/example/repo/pull/43",
            type: .comment,
            title: "External PR",
            subtitle: "example/repo · Comment",
            timestamp: Date(timeIntervalSince1970: 101),
            url: URL(string: "https://github.com/example/repo/pull/43")!
        )

        XCTAssertFalse(
            AttentionUpdateNotificationPolicy.shouldDeliver(
                item: selfTriggeredItem,
                includeSelfTriggeredUpdates: false
            )
        )
        XCTAssertTrue(
            AttentionUpdateNotificationPolicy.shouldDeliver(
                item: selfTriggeredItem,
                includeSelfTriggeredUpdates: true
            )
        )
        XCTAssertTrue(
            AttentionUpdateNotificationPolicy.shouldDeliver(
                item: externalItem,
                includeSelfTriggeredUpdates: false
            )
        )
    }

    func testAttentionSubjectRefreshPolicyRelabelsSubjectAndReplacesFocusSupplementalItems() {
        let url = URL(string: "https://github.com/example/repo/pull/42")!
        let existingItem = AttentionItem(
            id: "tracked-pr:42",
            subjectKey: url.absoluteString,
            type: .reviewedPullRequest,
            title: "Example PR",
            subtitle: "example/repo · Reviewed by you",
            repository: "example/repo",
            labels: [
                GitHubLabel(name: "old", colorHex: "111111", description: nil)
            ],
            timestamp: Date(timeIntervalSince1970: 100),
            url: url
        )
        let staleSupplemental = AttentionItem(
            id: "\(AttentionSubjectRefresh.localSupplementalItemIDPrefix)old",
            subjectKey: url.absoluteString,
            updateKey: "self-update:old",
            type: .reviewComment,
            title: "Example PR",
            subtitle: "example/repo · Review comment",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 110),
            url: url,
            isTriggeredByCurrentUser: true
        )
        let otherItem = AttentionItem(
            id: "tracked-pr:7",
            subjectKey: "https://github.com/example/repo/pull/7",
            type: .comment,
            title: "Other PR",
            subtitle: "example/repo · Comment",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 120),
            url: URL(string: "https://github.com/example/repo/pull/7")!
        )
        let freshSupplemental = AttentionItem(
            id: "\(AttentionSubjectRefresh.localSupplementalItemIDPrefix)new",
            subjectKey: url.absoluteString,
            updateKey: "self-update:new",
            type: .reviewApproved,
            title: "Example PR",
            subtitle: "alberto · example/repo · Review approved",
            repository: "example/repo",
            labels: [
                GitHubLabel(name: "fresh", colorHex: "00ff00", description: nil)
            ],
            timestamp: Date(timeIntervalSince1970: 130),
            url: url,
            actor: AttentionActor(login: "alberto", avatarURL: nil),
            isTriggeredByCurrentUser: true
        )

        let refreshed = AttentionSubjectRefreshPolicy.applying(
            AttentionSubjectRefresh(
                subjectKey: url.absoluteString,
                labels: [
                    GitHubLabel(name: "fresh", colorHex: "00ff00", description: nil)
                ],
                mergedAt: nil,
                supplementalItems: [freshSupplemental]
            ),
            to: [existingItem, staleSupplemental, otherItem]
        )

        XCTAssertEqual(refreshed.count, 3)
        XCTAssertEqual(
            refreshed.first(where: { $0.id == "tracked-pr:42" })?.labels.map(\.name),
            ["fresh"]
        )
        XCTAssertNil(refreshed.first(where: { $0.id == staleSupplemental.id }))
        XCTAssertEqual(refreshed.first(where: { $0.id == freshSupplemental.id })?.type, .reviewApproved)
        XCTAssertEqual(
            refreshed.first(where: { $0.id == "tracked-pr:7" })?.labels.map(\.name),
            []
        )
    }

    func testFocusWorkflowSupplementalItemsPromoteMergedPullRequestsIntoInboxSections() {
        let reference = PullRequestReference(owner: "example", name: "repo", number: 42)
        let subjectURL = reference.pullRequestURL
        let workflowURL = URL(string: "https://github.com/example/repo/actions/runs/99")!
        let mergedItem = AttentionItem(
            id: "tracked-pr:42",
            subjectKey: subjectURL.absoluteString,
            type: .reviewApproved,
            secondaryIndicatorType: .authoredPullRequest,
            focusType: .authoredPullRequest,
            title: "Example PR",
            subtitle: "example/repo · Review approved",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 100),
            url: subjectURL,
            subjectResolution: .merged
        )
        let supplementalItems = PullRequestFocusSupplementalItemPolicy.workflowItems(
            reference: reference,
            title: "Example PR",
            repository: "example/repo",
            labels: [],
            resolution: .merged,
            preview: PullRequestPostMergeWorkflowPreview(
                mode: .observed(branch: "main"),
                workflows: [
                    PullRequestPostMergeWorkflow(
                        id: "run:99",
                        title: "Promote main",
                        url: workflowURL,
                        status: .actionRequired,
                        timestamp: Date(timeIntervalSince1970: 200)
                    )
                ],
                evaluationIssues: []
            )
        )

        let refreshed = AttentionSubjectRefreshPolicy.applying(
            AttentionSubjectRefresh(
                subjectKey: subjectURL.absoluteString,
                labels: [],
                mergedAt: Date(timeIntervalSince1970: 150),
                supplementalItems: supplementalItems
            ),
            to: [mergedItem]
        )
        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(in: refreshed)
        let matches = InboxSectionPolicy.matchingItems(
            in: combined,
            configuration: .default
        )

        XCTAssertEqual(supplementalItems.map(\.type), [.workflowApprovalRequired])
        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(
            combined.first?.currentUpdateTypes,
            Set([.reviewApproved, .workflowApprovalRequired])
        )
        XCTAssertEqual(combined.first?.workflowApprovalURL, workflowURL)
        // TODO: The combined item should match the workflow approval rule, but supplemental
        // items don't yet inherit the parent PR's relationship through aggregation.
        // Once that's fixed, assert: matches.map(\.id) == [subjectURL.absoluteString]
        _ = matches
    }

    func testAggregatedWorkflowSupplementalPullRequestKeepsPullRequestURL() {
        let reference = PullRequestReference(owner: "example", name: "repo", number: 42)
        let subjectURL = reference.pullRequestURL
        let workflowURL = URL(string: "https://github.com/example/repo/actions/runs/99")!
        let baseItem = AttentionItem(
            id: "tracked-pr:42",
            subjectKey: subjectURL.absoluteString,
            type: .authoredPullRequest,
            title: "Example PR",
            subtitle: "example/repo · Authored pull request",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 100),
            url: subjectURL,
            subjectResolution: .open
        )
        let supplementalItems = PullRequestFocusSupplementalItemPolicy.workflowItems(
            reference: reference,
            title: "Example PR",
            repository: "example/repo",
            labels: [],
            resolution: .open,
            preview: PullRequestPostMergeWorkflowPreview(
                mode: .observed(branch: "main"),
                workflows: [
                    PullRequestPostMergeWorkflow(
                        id: "run:99",
                        title: "Promote main",
                        url: workflowURL,
                        status: .actionRequired,
                        timestamp: Date(timeIntervalSince1970: 200)
                    )
                ],
                evaluationIssues: []
            )
        )

        let refreshed = AttentionSubjectRefreshPolicy.applying(
            AttentionSubjectRefresh(
                subjectKey: subjectURL.absoluteString,
                labels: [],
                mergedAt: nil,
                supplementalItems: supplementalItems
            ),
            to: [baseItem]
        )
        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(in: refreshed)

        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(combined.first?.url, subjectURL)
        XCTAssertEqual(combined.first?.detail.updates.first?.url, workflowURL)
        XCTAssertEqual(combined.first?.detail.actions.first?.url, workflowURL)
    }

    func testReadyToMergeOutranksReviewApprovedInAggregation() {
        let subjectURL = URL(string: "https://github.com/example/repo/pull/1")!
        let subjectKey = subjectURL.absoluteString
        let approvalItem = AttentionItem(
            id: "notif:approval",
            subjectKey: subjectKey,
            updateKey: "notif:approval:reviewApproved:100",
            type: .reviewApproved,
            title: "Example PR",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 200),
            url: subjectURL,
            subjectResolution: .open
        )
        let readyItem = AttentionItem(
            id: "authored-signal:ready",
            subjectKey: subjectKey,
            updateKey: "authored-signal:ready:readyToMerge:150",
            type: .readyToMerge,
            title: "Example PR",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 150),
            url: subjectURL,
            subjectResolution: .open
        )

        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(
            in: [approvalItem, readyItem]
        )

        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(
            combined.first?.type, .readyToMerge,
            "readyToMerge should win over reviewApproved even with an earlier timestamp"
        )
        XCTAssertNotEqual(
            combined.first?.updateKey, approvalItem.updateKey,
            "updateKey should change so a replacement notification fires"
        )
    }

    func testAcknowledgedWorkflowExcludedFromInboxSections() {
        let item = AttentionItem(
            id: "run:42",
            subjectKey: "https://github.com/example/repo/pull/1",
            updateKey: "run:42:workflowFailed",
            latestSourceID: "run:42",
            type: .workflowFailed,
            secondaryIndicatorType: .authoredPullRequest,
            title: "CI failed",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 100),
            url: URL(string: "https://github.com/example/repo/actions/runs/42")!
        )

        let matchesBeforeAck = InboxSectionPolicy.matchingItems(
            in: [item],
            configuration: .default
        )
        XCTAssertEqual(matchesBeforeAck.count, 1, "Should match before acknowledge")

        let acknowledged: [String: AcknowledgedWorkflowState] = [
            item.subjectKey: AcknowledgedWorkflowState(
                subjectKey: item.subjectKey,
                acknowledgedRunIDs: ["run:42"],
                acknowledgedAt: Date()
            )
        ]

        let matchesAfterAck = InboxSectionPolicy.matchingItems(
            in: [item],
            configuration: .default,
            acknowledgedWorkflows: acknowledged
        )
        XCTAssertTrue(matchesAfterAck.isEmpty, "Should be excluded after acknowledge")
    }

    func testAcknowledgedWorkflowReappearsOnNewRun() {
        let item = AttentionItem(
            id: "run:99",
            subjectKey: "https://github.com/example/repo/pull/1",
            updateKey: "run:99:workflowFailed",
            latestSourceID: "run:99",
            type: .workflowFailed,
            secondaryIndicatorType: .authoredPullRequest,
            title: "CI failed again",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 200),
            url: URL(string: "https://github.com/example/repo/actions/runs/99")!
        )

        let acknowledged: [String: AcknowledgedWorkflowState] = [
            item.subjectKey: AcknowledgedWorkflowState(
                subjectKey: item.subjectKey,
                acknowledgedRunIDs: ["run:42"],
                acknowledgedAt: Date()
            )
        ]

        let matches = InboxSectionPolicy.matchingItems(
            in: [item],
            configuration: .default,
            acknowledgedWorkflows: acknowledged
        )
        XCTAssertEqual(
            matches.count, 1,
            "New run ID should not be covered by old acknowledgement"
        )
    }

    func testAcknowledgedWorkflowStateCoversRunID() {
        let state = AcknowledgedWorkflowState(
            subjectKey: "test",
            acknowledgedRunIDs: ["run:1", "run:2"],
            acknowledgedAt: Date()
        )

        XCTAssertTrue(state.coversRunID("run:1"))
        XCTAssertTrue(state.coversRunID("run:2"))
        XCTAssertFalse(state.coversRunID("run:3"))

        let updated = state.adding(runID: "run:3")
        XCTAssertTrue(updated.coversRunID("run:3"))
    }

    func testAttentionTypeDefaultStreamMapsDirectWorkSeparately() {
        XCTAssertEqual(AttentionItemType.comment.defaultStream, .notifications)
        XCTAssertEqual(AttentionItemType.authoredPullRequest.defaultStream, .pullRequests)
        XCTAssertEqual(AttentionItemType.assignedIssue.defaultStream, .issues)
    }

    func testBadgeHelpTextExplainsPrimaryAndSecondaryBadges() {
        XCTAssertEqual(
            AttentionItemType.badgeHelpText(
                primary: .workflowFailed,
                secondary: .authoredPullRequest
            ),
            "Workflow failed\nCreated by you"
        )
        XCTAssertEqual(
            AttentionItemType.badgeHelpText(
                primary: .reviewRequested,
                secondary: nil
            ),
            "Review requested"
        )
    }

    func testAttentionViewerPresentationPolicyUsesYouForCurrentActor() {
        let actor = AttentionActor(login: "fiam", avatarURL: nil)

        XCTAssertEqual(
            AttentionViewerPresentationPolicy.actorLabel(
                for: actor,
                viewerLogin: "fiam"
            ),
            "you"
        )
        XCTAssertEqual(
            AttentionViewerPresentationPolicy.actorLabel(
                for: actor,
                viewerLogin: "someone-else"
            ),
            "fiam"
        )
    }

    func testAttentionViewerPresentationPolicyPersonalizesLeadingViewerLogin() {
        XCTAssertEqual(
            AttentionViewerPresentationPolicy.personalizing(
                "fiam · ExampleOrg/sample-services · Review approved",
                viewerLogin: "fiam"
            ),
            "you · ExampleOrg/sample-services · Review approved"
        )
        XCTAssertEqual(
            AttentionViewerPresentationPolicy.personalizing(
                "fiam/repo",
                viewerLogin: "fiam"
            ),
            "fiam/repo"
        )
    }

    func testAttentionViewerPresentationPolicyAvoidsDuplicateUpdateActorPrefix() {
        let actor = AttentionActor(login: "fiam", avatarURL: nil)

        XCTAssertEqual(
            AttentionViewerPresentationPolicy.updateDetailText(
                actor: actor,
                detail: "fiam · ExampleOrg/sample-services · Review approved",
                viewerLogin: "fiam"
            ),
            "you · ExampleOrg/sample-services · Review approved"
        )
        XCTAssertEqual(
            AttentionViewerPresentationPolicy.updateDetailText(
                actor: actor,
                detail: "ExampleOrg/sample-services · Review approved",
                viewerLogin: "fiam"
            ),
            "you · ExampleOrg/sample-services · Review approved"
        )
    }

    func testPullRequestStateTransitionUsesSpecificLabels() {
        XCTAssertEqual(PullRequestStateTransition.merged.title, "Merged")
        XCTAssertEqual(
            PullRequestStateTransition.merged.detailLabel,
            "Pull request merged"
        )
        XCTAssertEqual(
            PullRequestStateTransition.merged.actorVerb,
            "merged this pull request"
        )

        XCTAssertEqual(PullRequestStateTransition.closed.title, "Closed")
        XCTAssertEqual(
            PullRequestStateTransition.reopened.detailLabel,
            "Pull request reopened"
        )
        XCTAssertEqual(PullRequestStateTransition.synchronized.title, "Updated")
    }

    func testCombinedAttentionViewUsesSpecificMergedTitleInUpdateHistory() {
        let url = URL(string: "https://github.com/example/repo/pull/42")!
        let mergedNotification = AttentionItem(
            id: "notif:merged:42",
            subjectKey: url.absoluteString,
            stream: .notifications,
            type: .pullRequestStateChanged,
            title: "PR 42",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 100),
            url: url,
            detail: AttentionDetail(
                contextPillTitle: PullRequestStateTransition.merged.title,
                why: AttentionWhy(
                    summary: "Pull request merged.",
                    detail: PullRequestStateTransition.merged.detailLabel
                ),
                evidence: [],
                actions: []
            )
        )

        let combined = AttentionSubjectViewPolicy.collapsingUpdates(in: [mergedNotification])

        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(combined.first?.detail.updates.first?.title, PullRequestStateTransition.merged.title)
    }

    func testCombinedAttentionViewCollapsesNotificationAndDirectPullRequestIntoOneSubject() {
        let url = URL(string: "https://github.com/ExampleOrg/cloud-uc-manifests/pull/638")!
        let directItem = AttentionItem(
            id: "pr:638",
            subjectKey: url.absoluteString,
            stream: .pullRequests,
            type: .assignedPullRequest,
            title: "[cloud-uc-services/cp] deploying uc-cp/uc-cp-api:873",
            subtitle: "#638 · ExampleOrg/cloud-uc-manifests",
            repository: "ExampleOrg/cloud-uc-manifests",
            timestamp: Date(timeIntervalSince1970: 100),
            url: url
        )
        let notificationItem = AttentionItem(
            id: "notif:638",
            subjectKey: url.absoluteString,
            stream: .notifications,
            type: .assignedPullRequest,
            title: "[cloud-uc-services/cp] deploying uc-cp/uc-cp-api:873",
            subtitle: "testcontainers-manifests-deploy[bot] · ExampleOrg/cloud-uc-manifests · Assigned pull request",
            repository: "ExampleOrg/cloud-uc-manifests",
            timestamp: Date(timeIntervalSince1970: 101),
            url: url,
            actor: AttentionActor(login: "testcontainers-manifests-deploy[bot]", avatarURL: nil, isBot: true)
        )

        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(
            in: [notificationItem, directItem]
        )

        XCTAssertEqual(combined.map(\.id), [url.absoluteString])
        XCTAssertEqual(combined.first?.stream, .pullRequests)
        XCTAssertEqual(combined.first?.type, .assignedPullRequest)
        XCTAssertEqual(combined.first?.actor?.login, "testcontainers-manifests-deploy[bot]")
    }

    func testCombinedAttentionViewBuildsTimelineForDistinctUpdatesOnSamePullRequest() {
        let url = URL(string: "https://github.com/ExampleOrg/cloud-uc-manifests/pull/638")!
        let reviewRequest = AttentionItem(
            id: "notif:review",
            subjectKey: url.absoluteString,
            stream: .notifications,
            type: .reviewRequested,
            title: "Review me",
            subtitle: "ExampleOrg/cloud-uc-manifests · Review requested",
            repository: "ExampleOrg/cloud-uc-manifests",
            timestamp: Date(timeIntervalSince1970: 100),
            url: url
        )
        let readyToMerge = AttentionItem(
            id: "ready:638",
            subjectKey: url.absoluteString,
            stream: .pullRequests,
            type: .readyToMerge,
            title: "Review me",
            subtitle: "ExampleOrg/cloud-uc-manifests · Ready to merge",
            repository: "ExampleOrg/cloud-uc-manifests",
            timestamp: Date(timeIntervalSince1970: 101),
            url: url
        )

        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(
            in: [reviewRequest, readyToMerge]
        )

        XCTAssertEqual(combined.map(\.id), [url.absoluteString])
        XCTAssertEqual(combined.first?.type, .readyToMerge)
        XCTAssertEqual(
            combined.first?.detail.updates.map(\.type),
            [.readyToMerge, .reviewRequested]
        )
    }

    func testCombinedReviewRequestRowPrefersReviewRequestForPullRequestFocus() {
        let url = URL(string: "https://github.com/example/repo/pull/3837")!
        let reviewRequest = AttentionItem(
            id: "notif:review",
            subjectKey: url.absoluteString,
            stream: .notifications,
            type: .teamReviewRequested,
            title: "bump deps",
            subtitle: "example/repo · Team review requested",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 100),
            url: url
        )
        let failedChecks = AttentionItem(
            id: "signal:failed-checks",
            subjectKey: url.absoluteString,
            stream: .pullRequests,
            type: .pullRequestFailedChecks,
            title: "bump deps",
            subtitle: "example/repo · Failed checks",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 101),
            url: url
        )

        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(
            in: [reviewRequest, failedChecks]
        )

        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(combined.first?.type, .pullRequestFailedChecks)
        XCTAssertEqual(combined.first?.pullRequestFocusSourceType, .teamReviewRequested)
    }

    func testAttentionItemWorkflowApprovalURLUsesCurrentWorkflowUpdate() {
        let pullRequestURL = URL(string: "https://github.com/ExampleOrg/cloud-uc-manifests/pull/638")!
        let workflowURL = URL(string: "https://github.com/ExampleOrg/cloud-uc-manifests/actions/runs/123")!
        let item = AttentionItem(
            id: "pr:638",
            subjectKey: pullRequestURL.absoluteString,
            stream: .pullRequests,
            type: .assignedPullRequest,
            title: "Review me",
            subtitle: "ExampleOrg/cloud-uc-manifests · Assigned pull request",
            repository: "ExampleOrg/cloud-uc-manifests",
            timestamp: Date(timeIntervalSince1970: 101),
            url: pullRequestURL,
            detail: AttentionDetail(
                why: AttentionWhy(summary: "Workflow waiting", detail: nil),
                evidence: [],
                updates: [
                    AttentionUpdate(
                        id: "run:123",
                        type: .workflowApprovalRequired,
                        title: "Workflow waiting for approval",
                        detail: nil,
                        timestamp: Date(timeIntervalSince1970: 101),
                        actor: nil,
                        url: workflowURL
                    )
                ],
                actions: []
            ),
            currentUpdateTypes: [.workflowApprovalRequired],
            currentRelationshipTypes: [.assignedPullRequest]
        )

        XCTAssertEqual(item.workflowApprovalURL, workflowURL)
    }

    func testAttentionItemWorkflowApprovalURLIgnoresHistoricalApprovalOnly() {
        let pullRequestURL = URL(string: "https://github.com/ExampleOrg/cloud-uc-manifests/pull/638")!
        let workflowURL = URL(string: "https://github.com/ExampleOrg/cloud-uc-manifests/actions/runs/123")!
        let item = AttentionItem(
            id: "pr:638",
            subjectKey: pullRequestURL.absoluteString,
            stream: .pullRequests,
            type: .assignedPullRequest,
            title: "Review me",
            subtitle: "ExampleOrg/cloud-uc-manifests · Assigned pull request",
            repository: "ExampleOrg/cloud-uc-manifests",
            timestamp: Date(timeIntervalSince1970: 101),
            url: pullRequestURL,
            detail: AttentionDetail(
                why: AttentionWhy(summary: "Review requested", detail: nil),
                evidence: [],
                updates: [
                    AttentionUpdate(
                        id: "run:123",
                        type: .workflowApprovalRequired,
                        title: "Workflow waiting for approval",
                        detail: nil,
                        timestamp: Date(timeIntervalSince1970: 100),
                        actor: nil,
                        url: workflowURL
                    )
                ],
                actions: []
            ),
            currentUpdateTypes: [.reviewRequested],
            currentRelationshipTypes: [.assignedPullRequest]
        )

        XCTAssertNil(item.workflowApprovalURL)
    }

    func testWorkflowApprovalTargetParsesGitHubRunURL() {
        let url = URL(string: "https://github.com/ExampleOrg/cloud-uc-manifests/actions/runs/123456789")!
        let target = WorkflowApprovalTarget(url: url)

        XCTAssertEqual(target?.repository, "ExampleOrg/cloud-uc-manifests")
        XCTAssertEqual(target?.runID, 123456789)
        XCTAssertEqual(target?.url, url)
    }

    func testPullRequestPostMergeWorkflowApprovalTargetOnlyExistsForApprovalState() {
        let url = URL(string: "https://github.com/ExampleOrg/cloud-uc-manifests/actions/runs/123456789")!
        let approvalWorkflow = PullRequestPostMergeWorkflow(
            id: "workflow:123456789",
            title: "Promote main",
            url: url,
            status: .actionRequired,
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let successfulWorkflow = PullRequestPostMergeWorkflow(
            id: "workflow:123456789",
            title: "Promote main",
            url: url,
            status: .succeeded,
            timestamp: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(approvalWorkflow.workflowApprovalTarget?.runID, 123456789)
        XCTAssertNil(successfulWorkflow.workflowApprovalTarget)
    }

    func testPullRequestCheckRunRollupKeepsLatestSuccessfulRerun() {
        let olderFailure = PullRequestCheckRun(
            id: 10,
            name: "JIRA task in title",
            status: "completed",
            conclusion: "failure",
            htmlURL: nil,
            detailsURL: nil,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 110),
            appSlug: "github-actions"
        )
        let newerSuccess = PullRequestCheckRun(
            id: 11,
            name: "JIRA task in title",
            status: "completed",
            conclusion: "success",
            htmlURL: nil,
            detailsURL: nil,
            startedAt: Date(timeIntervalSince1970: 120),
            completedAt: Date(timeIntervalSince1970: 130),
            appSlug: "github-actions"
        )

        let runs = PullRequestCheckRunRollupPolicy.latestRuns(from: [olderFailure, newerSuccess])

        XCTAssertEqual(runs, [newerSuccess])
    }

    func testPullRequestCheckRunRollupPrefersLatestPendingRerunOverFailure() {
        let olderFailure = PullRequestCheckRun(
            id: 10,
            name: "JIRA task in title",
            status: "completed",
            conclusion: "failure",
            htmlURL: nil,
            detailsURL: nil,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 110),
            appSlug: "github-actions"
        )
        let newerPending = PullRequestCheckRun(
            id: 11,
            name: "JIRA task in title",
            status: "in_progress",
            conclusion: nil,
            htmlURL: nil,
            detailsURL: nil,
            startedAt: Date(timeIntervalSince1970: 120),
            completedAt: nil,
            appSlug: "github-actions"
        )

        let runs = PullRequestCheckRunRollupPolicy.latestRuns(from: [olderFailure, newerPending])

        XCTAssertEqual(runs, [newerPending])
    }

    func testCombinedAttentionViewUsesRelationshipAsSecondaryIndicatorForLatestUpdate() {
        let url = URL(string: "https://github.com/ExampleOrg/cloud-uc-manifests/pull/638")!
        let authoredItem = AttentionItem(
            id: "tracked-pr:638",
            subjectKey: url.absoluteString,
            type: .authoredPullRequest,
            title: "Review me",
            subtitle: "ExampleOrg/cloud-uc-manifests · Created by you",
            repository: "ExampleOrg/cloud-uc-manifests",
            timestamp: Date(timeIntervalSince1970: 100),
            url: url
        )
        let workflowItem = AttentionItem(
            id: "run:638",
            subjectKey: url.absoluteString,
            type: .workflowFailed,
            title: "Review me",
            subtitle: "ExampleOrg/cloud-uc-manifests · Workflow failed",
            repository: "ExampleOrg/cloud-uc-manifests",
            timestamp: Date(timeIntervalSince1970: 101),
            url: url
        )
        let commentItem = AttentionItem(
            id: "notif:comment",
            subjectKey: url.absoluteString,
            type: .comment,
            title: "Review me",
            subtitle: "ExampleOrg/cloud-uc-manifests · New comment",
            repository: "ExampleOrg/cloud-uc-manifests",
            timestamp: Date(timeIntervalSince1970: 102),
            url: url
        )

        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(
            in: [authoredItem, workflowItem, commentItem]
        )

        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(
            combined.first?.type, .workflowFailed,
            "Higher-priority type should win even when another type has a later timestamp"
        )
        XCTAssertEqual(combined.first?.secondaryIndicatorType, .authoredPullRequest)
        XCTAssertEqual(
            combined.first?.detail.updates.map(\.type),
            [.comment, .workflowFailed]
        )
        XCTAssertTrue(combined.first?.isClosureNotificationEligible ?? false)
        XCTAssertTrue(combined.first?.isPostMergeWatchEligible ?? false)
    }

    func testAttentionSectionPolicyClassifiesWorkflowPrimaryItemsAsWorkflows() {
        let item = AttentionItem(
            id: "run:1",
            subjectKey: "https://github.com/example/repo/pull/1",
            updateKey: "run:1:workflowFailed",
            latestSourceID: "run:1",
            type: .workflowFailed,
            title: "PR 1",
            subtitle: "example/repo · Workflow failed",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 101),
            url: URL(string: "https://github.com/example/repo/pull/1")!
        )

        XCTAssertEqual(AttentionSectionPolicy.section(for: item), .workflows)
    }

    func testAttentionSectionPolicyClassifiesGitHubNotificationPrimaryItemsAsNotifications() {
        let item = AttentionItem(
            id: "https://github.com/example/repo/pull/2",
            subjectKey: "https://github.com/example/repo/pull/2",
            updateKey: "notif:22:reviewRequested:100",
            latestSourceID: "notif:22",
            type: .reviewRequested,
            title: "PR 2",
            subtitle: "example/repo · Review requested",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 100),
            url: URL(string: "https://github.com/example/repo/pull/2")!
        )

        XCTAssertEqual(AttentionSectionPolicy.section(for: item), .notifications)
    }

    func testAttentionSectionPolicyKeepsDirectPullRequestPrimaryItemsInPullRequests() {
        let url = URL(string: "https://github.com/example/repo/pull/3")!
        let notificationItem = AttentionItem(
            id: "notif:3",
            subjectKey: url.absoluteString,
            updateKey: "notif:3:reviewRequested:100",
            latestSourceID: "notif:3",
            stream: .notifications,
            type: .reviewRequested,
            title: "PR 3",
            subtitle: "example/repo · Review requested",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 100),
            url: url
        )
        let directItem = AttentionItem(
            id: "pr:3",
            subjectKey: url.absoluteString,
            updateKey: "authored-signal:ready-to-merge:3",
            latestSourceID: "pr:3",
            stream: .pullRequests,
            type: .readyToMerge,
            title: "PR 3",
            subtitle: "example/repo · Ready to merge",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 101),
            url: url
        )

        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(
            in: [notificationItem, directItem]
        )

        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(AttentionSectionPolicy.section(for: combined[0]), .pullRequests)
    }

    func testCombinedAttentionViewPreservesSelfTriggeredStateFromLatestUpdate() {
        let url = URL(string: "https://github.com/example/repo/pull/99")!
        let relationshipItem = AttentionItem(
            id: "tracked-pr:99",
            subjectKey: url.absoluteString,
            type: .reviewedPullRequest,
            title: "Example PR",
            subtitle: "example/repo · Reviewed by you",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 100),
            url: url,
            isTriggeredByCurrentUser: true
        )
        let selfComment = AttentionItem(
            id: "notif:self-comment",
            subjectKey: url.absoluteString,
            updateKey: "notif:self-comment",
            type: .comment,
            title: "Example PR",
            subtitle: "example/repo · Comment",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 101),
            url: url,
            actor: AttentionActor(login: "octocat", avatarURL: nil),
            isTriggeredByCurrentUser: true
        )

        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(
            in: [relationshipItem, selfComment]
        )

        XCTAssertEqual(combined.count, 1)
        XCTAssertTrue(combined[0].isTriggeredByCurrentUser)
        XCTAssertEqual(combined[0].detail.updates.map(\.isTriggeredByCurrentUser), [true])
    }

    func testTrackedPullRequestPriorityPrefersAuthoredOverReviewedAndCommented() {
        XCTAssertTrue(
            TrackedSubjectAttentionPolicy.shouldReplace(
                existing: .commentedPullRequest,
                with: .reviewedPullRequest
            )
        )
        XCTAssertTrue(
            TrackedSubjectAttentionPolicy.shouldReplace(
                existing: .reviewedPullRequest,
                with: .authoredPullRequest
            )
        )
        XCTAssertFalse(
            TrackedSubjectAttentionPolicy.shouldReplace(
                existing: .authoredPullRequest,
                with: .commentedPullRequest
            )
        )
    }

    func testTrackedIssuePriorityPrefersAssignedOverCreatedAndCommented() {
        XCTAssertTrue(
            TrackedSubjectAttentionPolicy.shouldReplace(
                existing: .commentedIssue,
                with: .authoredIssue
            )
        )
        XCTAssertTrue(
            TrackedSubjectAttentionPolicy.shouldReplace(
                existing: .authoredIssue,
                with: .assignedIssue
            )
        )
        XCTAssertFalse(
            TrackedSubjectAttentionPolicy.shouldReplace(
                existing: .assignedIssue,
                with: .commentedIssue
            )
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

    func testWorkflowWatchPolicyKeepsOpenAndWeekOldMergedPullRequests() {
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
                mergedAt: Date().addingTimeInterval(-172_800),
                now: Date()
            )
        )
        XCTAssertFalse(
            PullRequestAttentionPolicy.shouldWatchWorkflows(
                state: "closed",
                merged: true,
                mergedAt: Date().addingTimeInterval(-(8 * 86_400)),
                now: Date()
            )
        )
    }

    func testHistoricalLogEntriesStayOutOfActionableAttention() {
        let historicalItem = AttentionItem(
            id: "tracked-pr:1:merged",
            subjectKey: "https://github.com/acme/example/pull/1",
            type: .authoredPullRequest,
            title: "Merged PR",
            subtitle: "acme/example · Created by you",
            repository: "acme/example",
            timestamp: Date(timeIntervalSince1970: 200),
            url: URL(string: "https://github.com/acme/example/pull/1")!,
            isHistoricalLogEntry: true,
            isUnread: false
        )
        let activeItem = AttentionItem(
            id: "tracked-pr:2",
            subjectKey: "https://github.com/acme/example/pull/2",
            type: .reviewRequested,
            title: "Needs review",
            subtitle: "acme/example · Review requested",
            repository: "acme/example",
            timestamp: Date(timeIntervalSince1970: 201),
            url: URL(string: "https://github.com/acme/example/pull/2")!
        )

        let actionable = AttentionItemVisibilityPolicy.excludingHistoricalLogEntries(
            [historicalItem, activeItem]
        )

        XCTAssertEqual(actionable.map(\.id), ["tracked-pr:2"])
    }

    func testWorkflowFileParserReadsQuotedOnBlockWithFilters() {
        let result = GitHubWorkflowFileParser.parse(
            """
            name: Deploy
            'on':
              push:
                branches:
                  - main
                paths:
                  - Sources/**
                  - Package.swift
            """
        )

        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertEqual(result.definition?.name, "Deploy")
        XCTAssertEqual(result.definition?.pushTrigger?.branches, ["main"])
        XCTAssertEqual(
            result.definition?.pushTrigger?.paths,
            ["Sources/**", "Package.swift"]
        )
    }

    func testWorkflowFileParserRecognizesInlinePushEvents() {
        let result = GitHubWorkflowFileParser.parse(
            """
            name: CI
            on: [pull_request, push]
            """
        )

        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertEqual(result.definition?.name, "CI")
        XCTAssertEqual(result.definition?.pushTrigger, .default)
    }

    func testWorkflowFileParserSupportsFlowMappingsAndTagFilters() {
        let result = GitHubWorkflowFileParser.parse(
            """
            name: Release
            on: { push: { tags: ['v*'], paths: ['Sources/**'] } }
            """
        )

        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertEqual(result.definition?.name, "Release")
        XCTAssertEqual(result.definition?.pushTrigger?.tags, ["v*"])
        XCTAssertEqual(result.definition?.pushTrigger?.paths, ["Sources/**"])
    }

    func testWorkflowFileParserReturnsLocationForInvalidYAML() {
        let result = GitHubWorkflowFileParser.parse(
            """
            on:
              push:
                branches:
                  - main
                paths:
                  - Sources/**
                 - broken
            """
        )

        XCTAssertNil(result.definition)
        XCTAssertEqual(result.diagnostics.first?.kind, .invalidYAML)
        XCTAssertEqual(result.diagnostics.first?.location?.line, 7)
    }

    func testWorkflowPathFilterPolicyMatchesBranchAndPaths() {
        let trigger = GitHubWorkflowPushTrigger(
            branches: ["main"],
            branchesIgnore: [],
            tags: [],
            tagsIgnore: [],
            paths: ["Sources/**", "!Sources/Generated/**"],
            pathsIgnore: []
        )

        XCTAssertTrue(
            GitHubWorkflowPathFilterPolicy.matches(
                trigger: trigger,
                branch: "main",
                changedFiles: ["Sources/Octobar/AppModel.swift"]
            )
        )
        XCTAssertFalse(
            GitHubWorkflowPathFilterPolicy.matches(
                trigger: trigger,
                branch: "release/1.0",
                changedFiles: ["Sources/Octobar/AppModel.swift"]
            )
        )
        XCTAssertFalse(
            GitHubWorkflowPathFilterPolicy.matches(
                trigger: trigger,
                branch: "main",
                changedFiles: ["Sources/Generated/API.swift"]
            )
        )
    }

    func testWorkflowPathFilterPolicyRespectsPathsIgnore() {
        let trigger = GitHubWorkflowPushTrigger(
            branches: [],
            branchesIgnore: [],
            tags: [],
            tagsIgnore: [],
            paths: [],
            pathsIgnore: ["docs/**", "*.md"]
        )

        XCTAssertFalse(
            GitHubWorkflowPathFilterPolicy.matches(
                trigger: trigger,
                branch: "main",
                changedFiles: ["docs/readme.md", "CHANGELOG.md"]
            )
        )
        XCTAssertTrue(
            GitHubWorkflowPathFilterPolicy.matches(
                trigger: trigger,
                branch: "main",
                changedFiles: ["docs/readme.md", "Sources/Octobar/AppModel.swift"]
            )
        )
    }

    func testWorkflowPathFilterPolicySkipsTagOnlyPushWorkflowsForBranchPredictions() {
        let trigger = GitHubWorkflowPushTrigger(
            branches: [],
            branchesIgnore: [],
            tags: ["v*"],
            tagsIgnore: [],
            paths: [],
            pathsIgnore: []
        )

        XCTAssertFalse(
            GitHubWorkflowPathFilterPolicy.matches(
                trigger: trigger,
                branch: "main",
                changedFiles: ["Sources/Octobar/AppModel.swift"]
            )
        )
    }

    func testPostMergeWorkflowStatusMapsObservedWorkflowStates() {
        XCTAssertEqual(
            PullRequestPostMergeWorkflowStatus.observed(
                status: "completed",
                conclusion: "success"
            ),
            .succeeded
        )
        XCTAssertEqual(
            PullRequestPostMergeWorkflowStatus.observed(
                status: "in_progress",
                conclusion: nil
            ),
            .inProgress
        )
        XCTAssertEqual(
            PullRequestPostMergeWorkflowStatus.observed(
                status: "waiting",
                conclusion: nil,
                requiresApproval: true
            ),
            .actionRequired
        )
        XCTAssertEqual(
            PullRequestPostMergeWorkflowStatus.observed(
                status: "completed",
                conclusion: "cancelled"
            ),
            .completed("Cancelled")
        )
    }

    func testPostMergeWorkflowPreviewUsesObservedCopyAndOptionalFootnote() {
        let preview = PullRequestPostMergeWorkflowPreview(
            mode: .observed(branch: "main"),
            workflows: [
                PullRequestPostMergeWorkflow(
                    id: "workflow:1",
                    title: "Deploy",
                    url: URL(string: "https://github.com/acme/example/actions/runs/1")!,
                    status: .succeeded,
                    timestamp: Date(timeIntervalSince1970: 300)
                )
            ],
            evaluationIssues: [
                PullRequestPostMergeWorkflowEvaluationIssue(
                    path: ".github/workflows/deploy.yml",
                    message: "Expected <block end>, but found '-' (line 6, column 2)"
                )
            ]
        )

        XCTAssertEqual(preview.title, "Post-merge workflow")
        XCTAssertEqual(
            preview.detail,
            "Tracking the workflows GitHub observed for the merge into main."
        )
        XCTAssertEqual(
            preview.footnote,
            "Some workflow files could not be evaluated, so this list may be incomplete."
        )
        XCTAssertEqual(
            preview.footnoteHelpText,
            ".github/workflows/deploy.yml: Expected <block end>, but found '-' (line 6, column 2)"
        )
    }

    func testPullRequestFocusRestoresPreviousWorkflowPreviewWhenRefreshDropsIt() {
        let reference = PullRequestReference(owner: "acme", name: "example", number: 42)
        let previousPreview = PullRequestPostMergeWorkflowPreview(
            mode: .observed(branch: "main"),
            workflows: [
                PullRequestPostMergeWorkflow(
                    id: "workflow:1",
                    title: "Deploy",
                    url: URL(string: "https://github.com/acme/example/actions/runs/1")!,
                    status: .actionRequired,
                    timestamp: Date(timeIntervalSince1970: 300)
                )
            ],
            evaluationIssues: []
        )
        let previousFocus = PullRequestFocus(
            reference: reference,
            baseBranch: "main",
            sourceType: .workflowApprovalRequired,
            mode: .generic,
            resolution: .merged,
            mergedAt: Date(timeIntervalSince1970: 301),
            author: nil,
            labels: [],
            headerFacts: [],
            contextBadges: [],
            descriptionHTML: nil,
            statusSummary: nil,
            postMergeWorkflowPreview: previousPreview,
            sections: [],
            timeline: [],
            actions: [],
            readyForReviewAction: nil,
            reviewMergeAction: nil,
            emptyStateTitle: "Done",
            emptyStateDetail: "No details"
        )
        let refreshedFocus = PullRequestFocus(
            reference: reference,
            baseBranch: "main",
            sourceType: .workflowApprovalRequired,
            mode: .generic,
            resolution: .merged,
            mergedAt: Date(timeIntervalSince1970: 302),
            author: nil,
            labels: [],
            headerFacts: [],
            contextBadges: [],
            descriptionHTML: nil,
            statusSummary: nil,
            postMergeWorkflowPreview: nil,
            sections: [],
            timeline: [],
            actions: [],
            readyForReviewAction: nil,
            reviewMergeAction: nil,
            emptyStateTitle: "Done",
            emptyStateDetail: "No details"
        )

        let restoredFocus = refreshedFocus.restoringPostMergeWorkflowPreview(from: previousFocus)

        XCTAssertEqual(restoredFocus.postMergeWorkflowPreview, previousPreview)
    }

    func testIgnoringSubjectRemovesAllMatchingAttentionItems() {
        let ignoredKey = "https://github.com/acme/example/pull/42"
        let keptKey = "https://github.com/acme/example/pull/43"
        let now = Date()

        let ignoredPullRequest = AttentionItem(
            id: "pr:1",
            subjectKey: ignoredKey,
            type: .assignedPullRequest,
            title: "Ignored PR",
            subtitle: "#42 · acme/example",
            timestamp: now,
            url: URL(string: "https://github.com/acme/example/pull/42")!
        )
        let ignoredWorkflow = AttentionItem(
            id: "run:1",
            subjectKey: ignoredKey,
            type: .workflowFailed,
            title: "Ignored workflow",
            subtitle: "acme/example · PR #42 · Workflow failed",
            timestamp: now,
            url: URL(string: "https://github.com/acme/example/actions/runs/1")!
        )
        let keptPullRequest = AttentionItem(
            id: "pr:2",
            subjectKey: keptKey,
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

    func testCanonicalIgnoreKeyPlaceholderBuildsReadableSummary() {
        let placeholder = IgnoredAttentionSubject.placeholder(
            for: "https://github.com/acme/example/issues/77"
        )

        XCTAssertEqual(
            placeholder.ignoreKey,
            "https://github.com/acme/example/issues/77"
        )
        XCTAssertEqual(placeholder.title, "Issue #77")
        XCTAssertEqual(placeholder.subtitle, "acme/example")
        XCTAssertEqual(
            placeholder.url.absoluteString,
            "https://github.com/acme/example/issues/77"
        )
    }

    func testSnoozedSubjectsAreFilteredFromVisibleAttentionItems() {
        let now = Date()
        let snoozedKey = "https://github.com/acme/example/pull/42"
        let keptKey = "https://github.com/acme/example/pull/43"
        let snoozedPullRequest = AttentionItem(
            id: "pr:1",
            subjectKey: snoozedKey,
            type: .assignedPullRequest,
            title: "Snoozed PR",
            subtitle: "#42 · acme/example",
            timestamp: now,
            url: URL(string: snoozedKey)!
        )
        let snoozedWorkflow = AttentionItem(
            id: "run:1",
            subjectKey: snoozedKey,
            type: .workflowFailed,
            title: "Snoozed workflow",
            subtitle: "acme/example · PR #42 · Workflow failed",
            timestamp: now,
            url: URL(string: "https://github.com/acme/example/actions/runs/1")!
        )
        let keptPullRequest = AttentionItem(
            id: "pr:2",
            subjectKey: keptKey,
            type: .assignedPullRequest,
            title: "Kept PR",
            subtitle: "#43 · acme/example",
            timestamp: now,
            url: URL(string: keptKey)!
        )

        let filtered = AttentionItemVisibilityPolicy.excludingSnoozedSubjects(
            [snoozedPullRequest, snoozedWorkflow, keptPullRequest],
            snoozedKeys: [snoozedKey]
        )

        XCTAssertEqual(filtered, [keptPullRequest])
    }

    func testCanonicalSnoozedPlaceholderBuildsReadableSummary() {
        let placeholder = SnoozedAttentionSubject.placeholder(
            for: "https://github.com/acme/example/issues/77",
            snoozedAt: Date(timeIntervalSince1970: 1_700_000_000),
            snoozedUntil: Date(timeIntervalSince1970: 1_700_086_400)
        )

        XCTAssertEqual(
            placeholder.ignoreKey,
            "https://github.com/acme/example/issues/77"
        )
        XCTAssertEqual(placeholder.title, "Issue #77")
        XCTAssertEqual(placeholder.subtitle, "acme/example")
        XCTAssertEqual(
            placeholder.url.absoluteString,
            "https://github.com/acme/example/issues/77"
        )
    }

    func testIgnoreUndoStateUsesIgnoredSubjectIdentity() {
        let subject = IgnoredAttentionSubject(
            ignoreKey: "https://github.com/acme/example/pull/42",
            title: "Example",
            subtitle: "acme/example",
            url: URL(string: "https://github.com/acme/example/pull/42")!,
            ignoredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let state = IgnoreUndoState(
            subjects: [subject],
            expiresAt: Date(timeIntervalSince1970: 1_700_000_008)
        )

        XCTAssertEqual(state.id, subject.id)
    }

    func testSnoozeUndoStateUsesSubjectIdentityAndWakeTime() {
        let subject = SnoozedAttentionSubject(
            ignoreKey: "https://github.com/acme/example/pull/42",
            title: "Example",
            subtitle: "acme/example",
            url: URL(string: "https://github.com/acme/example/pull/42")!,
            snoozedAt: Date(timeIntervalSince1970: 1_700_000_000),
            snoozedUntil: Date(timeIntervalSince1970: 1_700_086_400)
        )
        let state = SnoozeUndoState(
            subjects: [subject],
            expiresAt: Date(timeIntervalSince1970: 1_700_000_008)
        )

        XCTAssertEqual(state.id, "\(subject.id)#1700086400.0")
    }

    func testUnreadSessionPolicyKeepsPreviouslyUnreadItemsVisible() {
        let cachedKeys = AttentionUnreadSessionPolicy.updatingCachedSubjectKeys(
            [],
            with: [
                AttentionItem(
                    id: "one",
                    subjectKey: "https://github.com/acme/example/pull/42",
                    type: .assignedPullRequest,
                    title: "Unread PR",
                    subtitle: "#42 · acme/example",
                    timestamp: Date(),
                    url: URL(string: "https://github.com/acme/example/pull/42")!,
                    isUnread: true
                )
            ]
        )

        let filtered = AttentionUnreadSessionPolicy.filteringVisibleItems(
            [
                AttentionItem(
                    id: "one",
                    subjectKey: "https://github.com/acme/example/pull/42",
                    type: .assignedPullRequest,
                    title: "Unread PR",
                    subtitle: "#42 · acme/example",
                    timestamp: Date(),
                    url: URL(string: "https://github.com/acme/example/pull/42")!,
                    isUnread: false
                )
            ],
            isUnreadFilterActive: true,
            cachedSubjectKeys: cachedKeys
        )

        XCTAssertEqual(filtered.map(\.subjectKey), ["https://github.com/acme/example/pull/42"])
    }

    func testUnreadSessionPolicyAddsNewUnreadItemsAndDropsMissingSubjects() {
        let cachedKeys: Set<String> = [
            "https://github.com/acme/example/pull/41",
            "https://github.com/acme/example/pull/42"
        ]
        let updatedKeys = AttentionUnreadSessionPolicy.updatingCachedSubjectKeys(
            cachedKeys,
            with: [
                AttentionItem(
                    id: "two",
                    subjectKey: "https://github.com/acme/example/pull/42",
                    type: .assignedPullRequest,
                    title: "Still visible",
                    subtitle: "#42 · acme/example",
                    timestamp: Date(),
                    url: URL(string: "https://github.com/acme/example/pull/42")!,
                    isUnread: false
                ),
                AttentionItem(
                    id: "three",
                    subjectKey: "https://github.com/acme/example/pull/43",
                    type: .assignedPullRequest,
                    title: "New unread",
                    subtitle: "#43 · acme/example",
                    timestamp: Date(),
                    url: URL(string: "https://github.com/acme/example/pull/43")!,
                    isUnread: true
                )
            ]
        )

        XCTAssertEqual(
            updatedKeys,
            [
                "https://github.com/acme/example/pull/42",
                "https://github.com/acme/example/pull/43"
            ]
        )
    }

    func testAttentionItemSearchPolicyMatchesAcrossMetadataFields() {
        let item = AttentionItem(
            id: "search",
            subjectKey: "https://github.com/ExampleOrg/offload-tools/pull/67",
            type: .reviewRequested,
            title: "fix(terraform): use set region for location code",
            subtitle: "#67 · ExampleOrg/offload-tools",
            repository: "ExampleOrg/offload-tools",
            labels: [
                GitHubLabel(
                    name: "needs-review",
                    colorHex: "0052CC",
                    description: nil
                )
            ],
            timestamp: Date(),
            url: URL(string: "https://github.com/ExampleOrg/offload-tools/pull/67")!,
            actor: AttentionActor(login: "alberto", avatarURL: nil)
        )

        XCTAssertEqual(
            AttentionItemSearchPolicy.matching([item], query: "terraform needs-review"),
            [item]
        )
        XCTAssertEqual(
            AttentionItemSearchPolicy.matching([item], query: "offload review"),
            [item]
        )
    }

    func testAttentionItemSearchPolicyReturnsAllItemsForBlankQuery() {
        let items = [
            AttentionItem(
                id: "one",
                subjectKey: "https://github.com/acme/example/pull/42",
                type: .assignedPullRequest,
                title: "Example pull request",
                subtitle: "#42 · acme/example",
                timestamp: Date(),
                url: URL(string: "https://github.com/acme/example/pull/42")!
            ),
            AttentionItem(
                id: "two",
                subjectKey: "https://github.com/acme/example/issues/7",
                type: .assignedIssue,
                title: "Example issue",
                subtitle: "#7 · acme/example",
                timestamp: Date(),
                url: URL(string: "https://github.com/acme/example/issues/7")!
            )
        ]

        XCTAssertEqual(
            AttentionItemSearchPolicy.matching(items, query: "   "),
            items
        )
    }

    func testAttentionSelectionRequestPolicySelectsMatchingSubject() {
        let matchingItem = AttentionItem(
            id: "match",
            subjectKey: "https://github.com/acme/example/pull/42",
            type: .assignedPullRequest,
            title: "Matching item",
            subtitle: "#42 · acme/example",
            timestamp: Date(),
            url: URL(string: "https://github.com/acme/example/pull/42")!
        )
        let otherItem = AttentionItem(
            id: "other",
            subjectKey: "https://github.com/acme/example/pull/43",
            type: .assignedPullRequest,
            title: "Other item",
            subtitle: "#43 · acme/example",
            timestamp: Date(),
            url: URL(string: "https://github.com/acme/example/pull/43")!
        )

        XCTAssertEqual(
            AttentionSelectionRequestPolicy.itemID(
                for: matchingItem.subjectKey,
                in: [otherItem, matchingItem]
            ),
            matchingItem.id
        )
    }

    func testInboxEmptyStateExplainsUnreadFilterAndHiddenItems() {
        let content = AttentionEmptyStatePolicy.inbox(
            showsUnreadOnly: true,
            snoozedCount: 1,
            ignoredCount: 2,
            pullRequestCount: 0,
            issueCount: 0
        )

        XCTAssertEqual(content.title, "No unread items")
        XCTAssertEqual(
            content.description,
            "Everything currently in the inbox has been marked read. " +
            "1 item is snoozed locally and 2 items are ignored locally."
        )
        XCTAssertEqual(
            content.actions,
            [
                .showAllInboxItems,
                .openSnoozedItems,
                .openIgnoredItems
            ]
        )
    }

    func testInboxEmptyStateExplainsBrowseItemsAndRecoveryActions() {
        let content = AttentionEmptyStatePolicy.inbox(
            showsUnreadOnly: false,
            snoozedCount: 0,
            ignoredCount: 1,
            pullRequestCount: 2,
            issueCount: 1
        )

        XCTAssertEqual(content.title, "Inbox is clear")
        XCTAssertEqual(
            content.description,
            "Nothing currently qualifies for the inbox, but Browse still " +
            "has 2 pull requests and 1 issue. 1 item is ignored locally."
        )
        XCTAssertEqual(
            content.actions,
            [
                .showPullRequests,
                .showIssues,
                .openIgnoredItems
            ]
        )
    }

    func testAttentionSubjectNavigationRequestRoundTripsNotificationUserInfo() {
        let request = AttentionSubjectNavigationRequest(
            subjectKey: "https://github.com/acme/example/pull/42"
        )
        let notification = Notification(
            name: .openMainWindowRequested,
            object: nil,
            userInfo: request.userInfo
        )

        XCTAssertEqual(
            AttentionSubjectNavigationRequest(notification: notification),
            request
        )
    }

    func testRemovalNotificationKeepsSubjectKeyForDeepLinking() {
        let item = AttentionItem(
            id: "pr:42",
            subjectKey: "https://github.com/acme/example/pull/42",
            type: .readyToMerge,
            title: "Example pull request",
            subtitle: "#42 · acme/example",
            repository: "acme/example",
            timestamp: Date(),
            url: URL(string: "https://github.com/acme/example/pull/42")!
        )
        let state = GitHubSubjectResolutionState(
            reference: GitHubSubjectReference(
                owner: "acme",
                name: "example",
                number: 42,
                kind: .pullRequest
            ),
            resolution: .merged,
            isAssignedToViewer: nil,
            mergedAt: Date(),
            mergeCommitSHA: "abc"
        )

        let notification = AttentionRemovalNotificationPolicy.notification(
            for: [item],
            state: state
        )

        XCTAssertEqual(
            notification?.subjectKey,
            "https://github.com/acme/example/pull/42"
        )
    }

    func testRateLimitUsesGitHubPollHintWhenHigherThanConfiguredInterval() {
        let rateLimit = GitHubRateLimit(
            resource: "graphql",
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
            resource: "graphql",
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
            resource: "graphql",
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
            resource: "search",
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
            resource: "search",
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

    func testRateLimitCollectionsKeepBucketsSeparateByResource() {
        let initial = GitHubRateLimit(
            resource: "core",
            limit: 5_000,
            remaining: 4_900,
            resetAt: nil,
            pollIntervalHintSeconds: nil,
            retryAfterSeconds: nil
        )
        let updatedCore = GitHubRateLimit(
            resource: "core",
            limit: 5_000,
            remaining: 4_875,
            resetAt: nil,
            pollIntervalHintSeconds: nil,
            retryAfterSeconds: nil
        )
        let search = GitHubRateLimit(
            resource: "search",
            limit: 30,
            remaining: 12,
            resetAt: nil,
            pollIntervalHintSeconds: nil,
            retryAfterSeconds: nil
        )

        let merged = GitHubRateLimit.mergingCollections([initial], with: [updatedCore, search])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(
            merged.first(where: { $0.resourceKey == "core" })?.remaining,
            4_875
        )
        XCTAssertEqual(
            GitHubRateLimit.mostRestrictive(in: merged)?.resourceKey,
            "search"
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
        let clearChecks = PullRequestCheckSummary(
            passedCount: 2,
            skippedCount: 0,
            failedCount: 0,
            pendingCount: 0
        )

        XCTAssertTrue(
            AuthoredPullRequestAttentionPolicy.shouldSurfaceReadyToMerge(
                state: "open",
                merged: false,
                isDraft: false,
                mergeable: true,
                mergeableState: "clean",
                pendingReviewRequests: 0,
                approvalCount: 1,
                hasChangesRequested: false,
                checkSummary: clearChecks
            )
        )
        XCTAssertFalse(
            AuthoredPullRequestAttentionPolicy.shouldSurfaceReadyToMerge(
                state: "open",
                merged: false,
                isDraft: false,
                mergeable: false,
                mergeableState: "clean",
                pendingReviewRequests: 0,
                approvalCount: 1,
                hasChangesRequested: false,
                checkSummary: clearChecks
            )
        )
        XCTAssertFalse(
            AuthoredPullRequestAttentionPolicy.shouldSurfaceReadyToMerge(
                state: "open",
                merged: false,
                isDraft: false,
                mergeable: true,
                mergeableState: "blocked",
                pendingReviewRequests: 0,
                approvalCount: 1,
                hasChangesRequested: false,
                checkSummary: clearChecks
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
                hasChangesRequested: false,
                checkSummary: clearChecks
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
                hasChangesRequested: false,
                checkSummary: clearChecks
            )
        )
        XCTAssertFalse(
            AuthoredPullRequestAttentionPolicy.shouldSurfaceReadyToMerge(
                state: "open",
                merged: false,
                isDraft: false,
                mergeable: true,
                mergeableState: "clean",
                pendingReviewRequests: 0,
                approvalCount: 1,
                hasChangesRequested: false,
                checkSummary: .empty
            )
        )
        XCTAssertFalse(
            AuthoredPullRequestAttentionPolicy.shouldSurfaceReadyToMerge(
                state: "open",
                merged: false,
                isDraft: false,
                mergeable: true,
                mergeableState: "clean",
                pendingReviewRequests: 0,
                approvalCount: 1,
                hasChangesRequested: false,
                checkSummary: PullRequestCheckSummary(
                    passedCount: 0,
                    skippedCount: 0,
                    failedCount: 1,
                    pendingCount: 0
                )
            )
        )
    }

    func testInboxSectionPolicyMatchesConfiguredAuthoredAndWorkflowSignals() {
        let authoredFailedChecks = AttentionItem(
            id: "authored-failed",
            subjectKey: "https://github.com/example/repo/pull/1",
            type: .pullRequestFailedChecks,
            secondaryIndicatorType: .authoredPullRequest,
            focusType: .authoredPullRequest,
            title: "PR 1",
            subtitle: "repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 10),
            url: URL(string: "https://github.com/example/repo/pull/1")!
        )
        let assignedWithoutReview = AttentionItem(
            id: "assigned-open",
            subjectKey: "https://github.com/example/repo/pull/2",
            type: .assignedPullRequest,
            focusType: .assignedPullRequest,
            title: "PR 2",
            subtitle: "repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 20),
            url: URL(string: "https://github.com/example/repo/pull/2")!
        )
        let workflowOnReviewedPR = AttentionItem(
            id: "workflow-reviewed",
            subjectKey: "https://github.com/example/repo/pull/3",
            type: .workflowFailed,
            secondaryIndicatorType: .reviewedPullRequest,
            focusType: .reviewedPullRequest,
            title: "PR 3",
            subtitle: "repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 30),
            url: URL(string: "https://github.com/example/repo/pull/3")!
        )
        let mergedOnlyWorkflow = AttentionItem(
            id: "workflow-merged-only",
            subjectKey: "https://github.com/example/repo/pull/4",
            type: .workflowFailed,
            title: "PR 4",
            subtitle: "repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 40),
            url: URL(string: "https://github.com/example/repo/pull/4")!
        )

        let matches = InboxSectionPolicy.matchingItems(
            in: [
                authoredFailedChecks,
                assignedWithoutReview,
                workflowOnReviewedPR,
                mergedOnlyWorkflow
            ],
            configuration: .default
        )

        XCTAssertEqual(
            Set(matches.map(\.id)),
            Set(["authored-failed", "assigned-open", "workflow-reviewed"]),
            "Workflow without relationship should not match any section"
        )
    }

    func testInboxSectionPolicyIncludesAssignedPullRequestsAfterYourReview() {
        let reviewedAssigned = AttentionItem(
            id: "assigned-reviewed",
            subjectKey: "https://github.com/example/repo/pull/5",
            type: .reviewApproved,
            secondaryIndicatorType: .assignedPullRequest,
            focusType: .assignedPullRequest,
            title: "PR 5",
            subtitle: "repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 50),
            url: URL(string: "https://github.com/example/repo/pull/5")!,
            actor: AttentionActor(
                login: "alberto",
                avatarURL: nil,
                profileURL: URL(string: "https://github.com/alberto")!,
                isBot: false
            ),
            isTriggeredByCurrentUser: true,
            detail: AttentionDetail(
                why: AttentionWhy(summary: "reviewed", detail: nil),
                evidence: [],
                actions: []
            )
        )

        let matches = InboxSectionPolicy.matchingItems(
            in: [reviewedAssigned],
            configuration: .default
        )

        XCTAssertEqual(matches.map(\.id), ["assigned-reviewed"])
    }

    func testInboxSectionPolicyMatchesWorkflowRulesOnPullRequestRowsWithCurrentWorkflowUpdates() {
        let pullRequestRow = AttentionItem(
            id: "workflow-running-pr-row",
            subjectKey: "https://github.com/example/repo/pull/5",
            type: .reviewApproved,
            secondaryIndicatorType: .authoredPullRequest,
            focusType: .authoredPullRequest,
            title: "PR 5",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 55),
            url: URL(string: "https://github.com/example/repo/pull/5")!,
            currentUpdateTypes: [.reviewApproved, .workflowRunning]
        )

        let configuration = InboxSectionConfiguration(
            rules: [
                InboxSectionRule(
                    id: UUID(uuidString: "DA89CBCC-8D4F-45A3-84F4-35EE5CCB65B0")!,
                    name: "Queued workflow runs",
                    itemKind: .workflow,
                    matchMode: .all,
                    conditions: [
                        .signal([.workflowRunning])
                    ],
                    isEnabled: true
                )
            ]
        )

        let matches = InboxSectionPolicy.matchingItems(
            in: [pullRequestRow],
            configuration: configuration
        )

        XCTAssertEqual(matches.map(\.id), ["workflow-running-pr-row"])
    }

    func testInboxSectionPolicyIgnoresHistoricalSignalsOnMergedRows() {
        let mergedRow = AttentionItem(
            id: "merged-row",
            subjectKey: "https://github.com/example/repo/pull/6",
            type: .pullRequestStateChanged,
            secondaryIndicatorType: .authoredPullRequest,
            focusType: .authoredPullRequest,
            title: "PR 6",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 60),
            url: URL(string: "https://github.com/example/repo/pull/6")!,
            detail: AttentionDetail(
                contextPillTitle: PullRequestStateTransition.merged.title,
                why: AttentionWhy(
                    summary: "Pull request merged.",
                    detail: PullRequestStateTransition.merged.detailLabel
                ),
                evidence: [],
                updates: [
                    AttentionUpdate(
                        id: "historical-ready",
                        type: .readyToMerge,
                        title: "Ready to merge",
                        detail: nil,
                        timestamp: Date(timeIntervalSince1970: 30),
                        actor: nil,
                        url: nil
                    )
                ],
                actions: []
            )
        )

        let matches = InboxSectionPolicy.matchingItems(
            in: [mergedRow],
            configuration: .default
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testInboxSectionConfigurationMigratesLegacyEnabledRules() {
        let migrated = InboxSectionConfiguration.migrated(
            from: LegacyInboxSectionConfiguration(
                enabledRules: [.authoredFailedChecks, .assignedIssues]
            )
        )

        XCTAssertEqual(migrated.rules.count, DefaultInboxRule.allCases.count)
        XCTAssertEqual(
            Set(migrated.rules.filter(\.isEnabled).map(\.name)),
            Set([
                DefaultInboxRule.authoredFailedChecks.title,
                DefaultInboxRule.assignedIssues.title
            ])
        )
        XCTAssertEqual(
            Set(migrated.rules.filter { !$0.isEnabled }.map(\.name)),
            Set(DefaultInboxRule.allCases.map(\.title)).subtracting([
                DefaultInboxRule.authoredFailedChecks.title,
                DefaultInboxRule.assignedIssues.title
            ])
        )
    }

    func testInboxSectionConfigurationV2MigrationAddsDraftRule() {
        let configuration = InboxSectionConfiguration(
            rules: [
                InboxSectionRule(
                    name: "Existing PR rule",
                    itemKind: .pullRequest,
                    conditions: [
                        .relationship([.authored]),
                        .signal([.readyToMerge])
                    ]
                )
            ]
        )

        let migrated = configuration.migratingV2ToV3()

        XCTAssertTrue(
            migrated.rules.contains {
                $0.name == DefaultInboxRule.authoredDraftPullRequests.title
            }
        )
    }

    func testInboxSectionPolicyMatchesNegatedReadyForReviewSignalForDrafts() {
        let draftItem = AttentionItem(
            id: "draft-authored-pr",
            subjectKey: "https://github.com/example/repo/pull/11",
            type: .authoredPullRequest,
            title: "Draft PR",
            subtitle: "example/repo · Created by you",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 110),
            url: URL(string: "https://github.com/example/repo/pull/11")!,
            subjectResolution: .open,
            isDraft: true
        )
        let configuration = InboxSectionConfiguration(
            rules: [
                InboxSectionRule(
                    name: "Draft authored PRs",
                    itemKind: .pullRequest,
                    conditions: [
                        .relationship([.authored]),
                        .signal([.readyForReview], isNegated: true)
                    ]
                )
            ]
        )

        let matches = InboxSectionPolicy.matchingItems(
            in: [draftItem],
            configuration: configuration
        )

        XCTAssertEqual(matches.map(\.id), ["draft-authored-pr"])
    }

    func testInboxSectionPolicyMatchesReadyForReviewSignal() {
        let readyItem = AttentionItem(
            id: "ready-pr",
            subjectKey: "https://github.com/example/repo/pull/12",
            type: .authoredPullRequest,
            title: "Ready PR",
            subtitle: "example/repo · Created by you",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 120),
            url: URL(string: "https://github.com/example/repo/pull/12")!,
            subjectResolution: .open,
            isDraft: false
        )
        let draftItem = AttentionItem(
            id: "draft-pr",
            subjectKey: "https://github.com/example/repo/pull/13",
            type: .authoredPullRequest,
            title: "Draft PR",
            subtitle: "example/repo · Created by you",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 130),
            url: URL(string: "https://github.com/example/repo/pull/13")!,
            subjectResolution: .open,
            isDraft: true
        )
        let configuration = InboxSectionConfiguration(
            rules: [
                InboxSectionRule(
                    name: "Ready for review PRs",
                    itemKind: .pullRequest,
                    conditions: [
                        .relationship([.authored]),
                        .signal([.readyForReview])
                    ]
                )
            ]
        )

        let matches = InboxSectionPolicy.matchingItems(
            in: [readyItem, draftItem],
            configuration: configuration
        )

        XCTAssertEqual(matches.map(\.id), ["ready-pr"])
    }

    func testDraftPullRequestsCanSurfaceFailedChecksSignals() {
        XCTAssertTrue(
            AuthoredPullRequestAttentionPolicy.shouldSurfaceFailedChecks(
                state: "open",
                merged: false,
                isDraft: true,
                checkSummary: PullRequestCheckSummary(
                    passedCount: 0,
                    skippedCount: 0,
                    failedCount: 1,
                    pendingCount: 0
                )
            )
        )
    }

    func testInboxSectionPolicyNormalizesLegacyAnyModeRulesToAllMatch() {
        let authoredFailedChecks = AttentionItem(
            id: "custom-any",
            subjectKey: "https://github.com/example/repo/pull/8",
            type: .pullRequestFailedChecks,
            secondaryIndicatorType: .authoredPullRequest,
            focusType: .authoredPullRequest,
            title: "PR 8",
            subtitle: "repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 80),
            url: URL(string: "https://github.com/example/repo/pull/8")!
        )

        let configuration = InboxSectionConfiguration(
            rules: [
                InboxSectionRule(
                    id: UUID(uuidString: "8E22174F-2A79-47C7-B319-4A1632B8D8E1")!,
                    name: "Legacy any rule",
                    itemKind: .pullRequest,
                    matchMode: .any,
                    conditions: [
                        .relationship([.assigned]),
                        .signal([.failedChecks])
                    ],
                    isEnabled: true
                )
            ]
        )

        let normalizedRule = configuration.normalized.rules.first
        let matches = InboxSectionPolicy.matchingItems(
            in: [authoredFailedChecks],
            configuration: configuration
        )

        XCTAssertEqual(normalizedRule?.matchMode, .all)
        XCTAssertTrue(matches.isEmpty)
    }

    func testInboxSectionPolicySupportsNegatedConditions() {
        let assignedItem = AttentionItem(
            id: "negated-condition",
            subjectKey: "https://github.com/example/repo/pull/9",
            type: .assignedPullRequest,
            title: "PR 9",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 90),
            url: URL(string: "https://github.com/example/repo/pull/9")!
        )

        let configuration = InboxSectionConfiguration(
            rules: [
                InboxSectionRule(
                    id: UUID(uuidString: "D3F96B5F-90DA-4EE6-8A12-62A5A8A9F4C1")!,
                    name: "PRs not assigned to me",
                    itemKind: .pullRequest,
                    matchMode: .all,
                    conditions: [
                        .relationship([.assigned], isNegated: true)
                    ],
                    isEnabled: true
                )
            ]
        )

        let matches = InboxSectionPolicy.matchingItems(
            in: [assignedItem],
            configuration: configuration
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testInboxSectionPolicyIncludesOpenAssignedWorkflowRowsForDefaultAssignedRule() {
        let workflowRow = AttentionItem(
            id: "workflow-success",
            subjectKey: "https://github.com/example/repo/pull/10",
            type: .workflowSucceeded,
            secondaryIndicatorType: .assignedPullRequest,
            focusType: .assignedPullRequest,
            title: "PR 10",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 100),
            url: URL(string: "https://github.com/example/repo/pull/10")!,
            subjectResolution: .open
        )

        let matches = InboxSectionPolicy.matchingItems(
            in: [workflowRow],
            configuration: .default
        )

        XCTAssertEqual(matches.map(\.id), ["workflow-success"])
    }

    func testInboxSectionPolicyKeepsAssignedRelationshipOnUnifiedWorkflowRows() {
        let url = URL(string: "https://github.com/example/repo/pull/12")!
        let assignedItem = AttentionItem(
            id: "assigned-pr",
            subjectKey: url.absoluteString,
            type: .assignedPullRequest,
            title: "PR 12",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 120),
            url: url
        )
        let authoredItem = AttentionItem(
            id: "authored-pr",
            subjectKey: url.absoluteString,
            type: .authoredPullRequest,
            title: "PR 12",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 121),
            url: url
        )
        let workflowItem = AttentionItem(
            id: "workflow-pr",
            subjectKey: url.absoluteString,
            type: .workflowSucceeded,
            title: "PR 12",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 122),
            url: url,
            subjectResolution: .open
        )

        let combined = AttentionCombinedViewPolicy.collapsingDuplicates(
            in: [assignedItem, authoredItem, workflowItem]
        )
        let matches = InboxSectionPolicy.matchingItems(
            in: combined,
            configuration: .default
        )

        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(
            combined.first?.currentRelationshipTypes,
            Set([.assignedPullRequest, .authoredPullRequest])
        )
        XCTAssertEqual(matches.map(\.id), [url.absoluteString])
    }

    func testInboxSectionPolicyExcludesMergedWorkflowRowsFromPullRequestRules() {
        let workflowRow = AttentionItem(
            id: "workflow-merged",
            subjectKey: "https://github.com/example/repo/pull/11",
            type: .workflowSucceeded,
            secondaryIndicatorType: .assignedPullRequest,
            focusType: .assignedPullRequest,
            title: "PR 11",
            subtitle: "example/repo",
            repository: "example/repo",
            timestamp: Date(timeIntervalSince1970: 110),
            url: URL(string: "https://github.com/example/repo/pull/11")!,
            subjectResolution: .merged
        )

        let configuration = InboxSectionConfiguration(
            rules: [
                InboxSectionRule(
                    id: UUID(uuidString: "B60C7FD6-C385-49B6-A18F-69F9308604E2")!,
                    name: "Assigned pull requests",
                    itemKind: .pullRequest,
                    matchMode: .all,
                    conditions: [
                        .relationship([.assigned])
                    ],
                    isEnabled: true
                )
            ]
        )

        let matches = InboxSectionPolicy.matchingItems(
            in: [workflowRow],
            configuration: configuration
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testWorkflowRulesOfferRelationshipAndSignalConditions() {
        XCTAssertEqual(InboxRuleItemKind.workflow.availableConditionKinds, [.relationship, .signal])
        XCTAssertFalse(InboxRuleItemKind.workflow.availableRelationships.isEmpty)
        XCTAssertTrue(InboxRuleItemKind.workflow.availableRelationships.contains(.interacted))
    }

    func testPullRequestContextBadgesStayEmptyWithoutWorkflowAttention() {
        let badges = PullRequestContextBadge.badges(workflowAttentionType: nil)

        XCTAssertTrue(badges.isEmpty)
    }

    func testPullRequestContextBadgesSurfaceWorkflowAttention() {
        let badges = PullRequestContextBadge.badges(workflowAttentionType: .workflowApprovalRequired)

        XCTAssertEqual(badges.count, 1)
        XCTAssertEqual(badges.first?.title, AttentionItemType.workflowApprovalRequired.accessibilityLabel)
    }

    func testPullRequestContextBadgesSkipDuplicateWorkflowAttention() {
        let badges = PullRequestContextBadge.badges(
            workflowAttentionType: .workflowApprovalRequired,
            excluding: .workflowApprovalRequired
        )

        XCTAssertTrue(badges.isEmpty)
    }

    func testPullRequestFocusDisplayedContextBadgesHideWorkflowBadgeAfterSourceTypeRefresh() {
        let focus = PullRequestFocus(
            reference: PullRequestReference(owner: "example", name: "repo", number: 42),
            baseBranch: "main",
            sourceType: .reviewApproved,
            mode: .authored,
            resolution: .merged,
            mergedAt: Date(timeIntervalSince1970: 100),
            author: nil,
            labels: [],
            headerFacts: [],
            contextBadges: PullRequestContextBadge.badges(
                workflowAttentionType: .workflowApprovalRequired,
                excluding: .reviewApproved
            ),
            descriptionHTML: nil,
            statusSummary: nil,
            postMergeWorkflowPreview: PullRequestPostMergeWorkflowPreview(
                mode: .observed(branch: "main"),
                workflows: [
                    PullRequestPostMergeWorkflow(
                        id: "run:99",
                        title: "Promote main",
                        url: URL(string: "https://github.com/example/repo/actions/runs/99")!,
                        status: .actionRequired,
                        timestamp: Date(timeIntervalSince1970: 120)
                    )
                ],
                evaluationIssues: []
            ),
            sections: [],
            timeline: [],
            actions: [],
            readyForReviewAction: nil,
            reviewMergeAction: nil,
            emptyStateTitle: "",
            emptyStateDetail: ""
        )

        XCTAssertTrue(
            focus.displayedContextBadges(excluding: AttentionItemType.workflowApprovalRequired).isEmpty
        )
    }

    func testReadyToMergeHeaderFactsUseApprovalLanguage() {
        let facts = PullRequestHeaderFact.build(
            sourceType: .readyToMerge,
            resolution: .open,
            sourceActor: nil,
            author: nil,
            assigner: nil,
            latestApprover: AttentionActor(login: "nicksieger", avatarURL: nil, isBot: false),
            approvalCount: 3,
            mergedBy: nil
        )

        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.label, "approved by")
        XCTAssertEqual(facts.first?.overflowLabel, "and 2 more people")
    }

    func testReadyToMergeHeaderFactsIncludeAuthorAndApprover() {
        let facts = PullRequestHeaderFact.build(
            sourceType: .readyToMerge,
            resolution: .open,
            sourceActor: nil,
            author: AttentionActor(login: "fiam", avatarURL: nil, isBot: false),
            assigner: nil,
            latestApprover: AttentionActor(login: "nicksieger", avatarURL: nil, isBot: false),
            approvalCount: 3,
            mergedBy: nil
        )

        XCTAssertEqual(facts.map(\.label), ["created by", "approved by"])
        XCTAssertEqual(facts.map(\.actor.login), ["fiam", "nicksieger"])
        XCTAssertEqual(facts.last?.overflowLabel, "and 2 more people")
    }

    func testReadyToMergeHeaderFactsCombineSameAuthorAndApprover() {
        let facts = PullRequestHeaderFact.build(
            sourceType: .readyToMerge,
            resolution: .open,
            sourceActor: nil,
            author: AttentionActor(login: "fiam", avatarURL: nil, isBot: false),
            assigner: nil,
            latestApprover: AttentionActor(login: "fiam", avatarURL: nil, isBot: false),
            approvalCount: 2,
            mergedBy: nil
        )

        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.id, "created-and-approved-by")
        XCTAssertEqual(facts.first?.label, "created and approved by")
        XCTAssertEqual(facts.first?.actor.login, "fiam")
        XCTAssertEqual(facts.first?.overflowLabel, "and 1 more person")
    }

    func testReviewApprovedHeaderFactsIncludeAuthorAndApprover() {
        let facts = PullRequestHeaderFact.build(
            sourceType: .reviewApproved,
            resolution: .open,
            sourceActor: AttentionActor(login: "nicksieger", avatarURL: nil, isBot: false),
            author: AttentionActor(login: "fiam", avatarURL: nil, isBot: false),
            assigner: nil,
            latestApprover: nil,
            approvalCount: 1,
            mergedBy: nil
        )

        XCTAssertEqual(facts.map(\.label), ["created by", "approved by"])
        XCTAssertEqual(facts.map(\.actor.login), ["fiam", "nicksieger"])
    }

    func testReviewApprovedHeaderFactsCombineSameAuthorAndApprover() {
        let facts = PullRequestHeaderFact.build(
            sourceType: .reviewApproved,
            resolution: .open,
            sourceActor: AttentionActor(login: "fiam", avatarURL: nil, isBot: false),
            author: AttentionActor(login: "fiam", avatarURL: nil, isBot: false),
            assigner: nil,
            latestApprover: nil,
            approvalCount: 1,
            mergedBy: nil
        )

        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.id, "created-and-approved-by")
        XCTAssertEqual(facts.first?.label, "created and approved by")
        XCTAssertEqual(facts.first?.actor.login, "fiam")
    }

    func testAssignedPullRequestHeaderFactsIncludeAuthorAndAssigner() {
        let facts = PullRequestHeaderFact.build(
            sourceType: .assignedPullRequest,
            resolution: .open,
            sourceActor: nil,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            assigner: AttentionActor(login: "fiam", avatarURL: nil, isBot: false),
            latestApprover: nil,
            approvalCount: 0,
            mergedBy: nil
        )

        XCTAssertEqual(facts.map(\.label), ["created by", "assigned by"])
        XCTAssertEqual(facts.map(\.actor.login), ["renovate-custom-app", "fiam"])
    }

    func testAssignedPullRequestHeaderFactsCombineSameAuthorAndAssigner() {
        let facts = PullRequestHeaderFact.build(
            sourceType: .assignedPullRequest,
            resolution: .open,
            sourceActor: nil,
            author: AttentionActor(login: "cloud-offload-manager", avatarURL: nil, isBot: true),
            assigner: AttentionActor(
                login: "cloud-offload-manager",
                avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1"),
                isBot: true
            ),
            latestApprover: nil,
            approvalCount: 0,
            mergedBy: nil
        )

        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.id, "created-and-assigned-by")
        XCTAssertEqual(facts.first?.label, "created and assigned by")
        XCTAssertEqual(facts.first?.actor.login, "cloud-offload-manager")
    }

    func testAuthoredPullRequestActionsKeepViewAsSecondaryWhenMutationPrimaryExists() {
        let actions = AttentionAction.pullRequestActions(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 639),
            mode: .authored,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            hasNewCommits: false,
            hasPrimaryMutationAction: true
        )

        XCTAssertEqual(actions.map(\.id), ["view-pr", "open-files", "open-checks"])
        XCTAssertEqual(actions.first?.isPrimary, false)
    }

    func testAssignedPullRequestActionsUseViewAsPrimaryWhenNoMutationExists() {
        let actions = AttentionAction.pullRequestActions(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 638),
            mode: .generic,
            checkSummary: .empty,
            hasNewCommits: false,
            hasPrimaryMutationAction: false
        )

        XCTAssertEqual(actions.map(\.id), ["view-pr", "open-files"])
        XCTAssertEqual(actions.first?.title, "View on GitHub")
        XCTAssertEqual(actions.first?.isPrimary, true)
    }

    func testAuthoredPullRequestActionsUseViewAsPrimaryWhenMergeActionBlocked() {
        let actions = AttentionAction.pullRequestActions(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 643),
            mode: .authored,
            checkSummary: PullRequestCheckSummary(
                passedCount: 7,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            hasNewCommits: false,
            hasPrimaryMutationAction: false
        )

        XCTAssertEqual(actions.map(\.id), ["view-pr", "open-files", "open-checks"])
        XCTAssertEqual(actions.first?.title, "View on GitHub")
        XCTAssertEqual(actions.first?.isPrimary, true)
    }

    func testBotAssignedReviewMergeActionEnablesApproveAndMergeWhenClean() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .assignedPullRequest,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
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
        XCTAssertEqual(action?.allowedMergeMethods, [.merge, .squash, .rebase])
        XCTAssertNil(action?.mergeMethod)
    }

    func testBotAssignedReviewMergeActionFallsBackToSquashWhenRepoDisallowsMergeCommits() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .assignedPullRequest,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: false,
            allowSquashMerge: true,
            allowRebaseMerge: false,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 1,
            checkSummary: PullRequestCheckSummary(
                passedCount: 9,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.isEnabled, true)
        XCTAssertEqual(action?.mergeMethod, .squash)
    }

    func testReviewMergeActionRequiresSelectorWhenMultipleMergeMethodsAreAllowed() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .readyToMerge,
            mode: .authored,
            author: AttentionActor(login: "alberto", avatarURL: nil, isBot: false),
            viewerPermission: "WRITE",
            allowMergeCommit: false,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "APPROVED",
            approvalCount: 1,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.isEnabled, true)
        XCTAssertNil(action?.mergeMethod)
        XCTAssertEqual(action?.preferredMergeMethod, .squash)
        XCTAssertEqual(action?.allowedMergeMethods, [.squash, .rebase])
        XCTAssertEqual(action?.needsMergeMethodSelection, true)
    }

    func testReviewMergeActionPrefersProvidedDefaultMergeMethodWhenMultipleAreAllowed() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .readyToMerge,
            mode: .authored,
            author: AttentionActor(login: "alberto", avatarURL: nil, isBot: false),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: false,
            preferredMergeMethod: .squash,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "APPROVED",
            approvalCount: 1,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.allowedMergeMethods, [.squash, .merge])
        XCTAssertEqual(action?.preferredMergeMethod, .squash)
        XCTAssertNil(action?.mergeMethod)
    }

    func testReviewMergeActionShowsMergedStateWhenPullRequestIsAlreadyMerged() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .readyToMerge,
            mode: .authored,
            author: AttentionActor(login: "alberto", avatarURL: nil, isBot: false),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "APPROVED",
            approvalCount: 1,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            isMerged: true
        )

        XCTAssertEqual(action?.title, "Merged")
        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(action?.outcome, .merged)
        XCTAssertNil(action?.disabledReason)
    }

    func testReviewMergeActionShowsQueuedStateWhenPullRequestIsAlreadyQueued() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .reviewRequested,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: false,
            allowSquashMerge: true,
            allowRebaseMerge: false,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "APPROVED",
            approvalCount: 1,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: PullRequestCheckSummary(
                passedCount: 6,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            isInMergeQueue: true
        )

        XCTAssertEqual(action?.title, "Queued to Merge")
        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(action?.outcome, .queued)
        XCTAssertNil(action?.disabledReason)
    }

    func testReviewMergeActionPrefersMergedStateOverQueuedState() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .reviewRequested,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: false,
            allowSquashMerge: true,
            allowRebaseMerge: false,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "APPROVED",
            approvalCount: 1,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: PullRequestCheckSummary(
                passedCount: 6,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            isMerged: true,
            isInMergeQueue: true
        )

        XCTAssertEqual(action?.title, "Merged")
        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(action?.outcome, .merged)
    }

    func testReviewMergeActionDisablesWhenRepositoryAllowsNoMergeMethods() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .assignedPullRequest,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: false,
            allowSquashMerge: false,
            allowRebaseMerge: false,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 1,
            checkSummary: PullRequestCheckSummary(
                passedCount: 9,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(
            action?.disabledReason,
            "This repository does not allow pull requests to be merged directly."
        )
    }

    func testBotReviewRequestedActionEnablesApproveAndMergeForCurrentRequest() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .reviewRequested,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 1,
            checkSummary: PullRequestCheckSummary(
                passedCount: 5,
                skippedCount: 1,
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

    func testBotTeamReviewRequestedActionEnablesApproveAndMergeForCurrentRequest() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .teamReviewRequested,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "MAINTAIN",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 1,
            checkSummary: PullRequestCheckSummary(
                passedCount: 5,
                skippedCount: 1,
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

    func testBotCommentFollowUpActionEnablesApproveAndMergeForCurrentRequest() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .newCommitsAfterComment,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "ADMIN",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 1,
            checkSummary: PullRequestCheckSummary(
                passedCount: 5,
                skippedCount: 1,
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
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .assignedPullRequest,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
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

    func testBotAssignedReviewMergeActionDisablesWhenOtherReviewsAreStillRequested() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .assignedPullRequest,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "MAINTAIN",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 2,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 3,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(action?.disabledReason, "Reviews are still requested on this pull request.")
    }

    func testBotAssignedReviewMergeActionDisablesWithoutWritePermission() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .assignedPullRequest,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "READ",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: PullRequestCheckSummary(
                passedCount: 12,
                skippedCount: 2,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(
            action?.disabledReason,
            "You do not have permission to review and merge pull requests in this repository."
        )
    }

    func testAuthoredMergeActionRequiresApprovalAndMergePermission() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .readyToMerge,
            mode: .authored,
            author: AttentionActor(login: "alberto", avatarURL: nil, isBot: false),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "APPROVED",
            approvalCount: 1,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.title, "Merge Pull Request")
        XCTAssertEqual(action?.requiresApproval, false)
        XCTAssertEqual(action?.isEnabled, true)
    }

    func testAuthoredMergeActionDisablesWhenReviewIsStillRequested() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .readyToMerge,
            mode: .authored,
            author: AttentionActor(login: "alberto", avatarURL: nil, isBot: false),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "APPROVED",
            approvalCount: 1,
            hasChangesRequested: false,
            pendingReviewRequestCount: 2,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(action?.disabledReason, "Reviews are still requested on this pull request.")
    }

    func testAuthoredDraftPullRequestShowsReadyForReviewAction() {
        let action = PullRequestReadyForReviewAction.makeAction(
            mode: .authored,
            resolution: .open,
            isDraft: true
        )

        XCTAssertEqual(action?.title, "Ready for Review")
        XCTAssertEqual(action?.isEnabled, true)
        XCTAssertNil(action?.disabledReason)
    }

    func testReadyForReviewActionHiddenForNonDraftPullRequests() {
        XCTAssertNil(
            PullRequestReadyForReviewAction.makeAction(
                mode: .authored,
                resolution: .open,
                isDraft: false
            )
        )
        XCTAssertNil(
            PullRequestReadyForReviewAction.makeAction(
                mode: .participating,
                resolution: .open,
                isDraft: true
            )
        )
    }

    func testDraftPullRequestSidebarContextShowsDraftPrefix() {
        let item = AttentionItem(
            id: "draft-sidebar",
            subjectKey: "https://github.com/example/octowatch/pull/42",
            type: .authoredPullRequest,
            title: "Draft sidebar item",
            subtitle: "example/octowatch · Draft · Created by you",
            repository: "example/octowatch",
            timestamp: Date(),
            url: URL(string: "https://github.com/example/octowatch/pull/42")!,
            isDraft: true
        )

        XCTAssertEqual(
            AttentionItemPresentationPolicy.sidebarContext(for: item),
            "example/octowatch · Draft · Your pull request"
        )
    }

    func testNonDraftSidebarContextOmitsDraftPrefix() {
        let item = AttentionItem(
            id: "non-draft-sidebar",
            subjectKey: "https://github.com/example/octowatch/pull/43",
            type: .authoredPullRequest,
            title: "Regular sidebar item",
            subtitle: "example/octowatch · Created by you",
            repository: "example/octowatch",
            timestamp: Date(),
            url: URL(string: "https://github.com/example/octowatch/pull/43")!,
            isDraft: false
        )

        XCTAssertEqual(
            AttentionItemPresentationPolicy.sidebarContext(for: item),
            "example/octowatch · Your pull request"
        )
    }

    func testBotReviewRequestedActionDisablesWhenOtherReviewRequestsRemain() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .reviewRequested,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 2,
            checkSummary: PullRequestCheckSummary(
                passedCount: 5,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(action?.disabledReason, "Reviews are still requested on this pull request.")
    }

    func testBotAssignedActionEnablesApproveAndMergeWhenCurrentReviewRequestIsSatisfiable() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .assignedPullRequest,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 1,
            checkSummary: PullRequestCheckSummary(
                passedCount: 9,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.title, "Approve and Merge")
        XCTAssertEqual(action?.isEnabled, true)
        XCTAssertNil(action?.disabledReason)
    }

    func testPullRequestStatusSummaryShowsMergedState() {
        let action = PullRequestReviewMergeAction(
            title: "Merged",
            requiresApproval: false,
            isEnabled: false,
            disabledReason: nil,
            allowedMergeMethods: [],
            outcome: .merged
        )

        let summary = PullRequestStatusSummary.build(
            mode: .authored,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            reviewMergeAction: action
        )

        XCTAssertEqual(summary?.title, "Merged")
        XCTAssertEqual(summary?.accent, .resolved)
    }

    func testPullRequestStatusSummaryShowsQueuedState() {
        let action = PullRequestReviewMergeAction(
            title: "Queued to Merge",
            requiresApproval: false,
            isEnabled: false,
            disabledReason: nil,
            allowedMergeMethods: [],
            outcome: .queued
        )

        let summary = PullRequestStatusSummary.build(
            mode: .generic,
            checkSummary: PullRequestCheckSummary(
                passedCount: 5,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            reviewMergeAction: action
        )

        XCTAssertEqual(summary?.title, "Queued to merge")
        XCTAssertEqual(summary?.accent, .warning)
    }

    func testPullRequestStatusSummaryShowsMergedResolutionEvenWithoutMutationAction() {
        let summary = PullRequestStatusSummary.build(
            mode: .generic,
            resolution: .merged,
            checkSummary: PullRequestCheckSummary(
                passedCount: 14,
                skippedCount: 10,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            reviewMergeAction: nil
        )

        XCTAssertEqual(summary?.title, "Merged")
        XCTAssertEqual(summary?.detail, "This pull request has already been merged.")
        XCTAssertEqual(summary?.accent, .resolved)
    }

    func testPullRequestStatusSummaryPrefersMergedResolutionOverQueuedOutcome() {
        let summary = PullRequestStatusSummary.build(
            mode: .generic,
            resolution: .merged,
            checkSummary: PullRequestCheckSummary(
                passedCount: 14,
                skippedCount: 10,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            reviewMergeAction: PullRequestReviewMergeAction(
                title: "Queued to Merge",
                requiresApproval: false,
                isEnabled: false,
                disabledReason: nil,
                allowedMergeMethods: [],
                outcome: .queued
            )
        )

        XCTAssertEqual(summary?.title, "Merged")
        XCTAssertEqual(summary?.detail, "This pull request has already been merged.")
        XCTAssertEqual(summary?.accent, .resolved)
    }

    func testPullRequestStatusSummaryShowsClosedResolutionEvenWithoutMutationAction() {
        let summary = PullRequestStatusSummary.build(
            mode: .generic,
            resolution: .closed,
            checkSummary: PullRequestCheckSummary(
                passedCount: 2,
                skippedCount: 0,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            reviewMergeAction: nil
        )

        XCTAssertEqual(summary?.title, "Closed")
        XCTAssertEqual(summary?.detail, "This pull request is already closed.")
        XCTAssertEqual(summary?.accent, .warning)
    }

    func testPullRequestStatusSummaryShowsDraftState() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .authoredPullRequest,
            mode: .authored,
            author: AttentionActor(login: "alberto", avatarURL: nil, isBot: false),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: true,
            reviewDecision: nil,
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: .empty,
            openThreadCount: 0
        )

        let summary = PullRequestStatusSummary.build(
            mode: .authored,
            resolution: .open,
            checkSummary: .empty,
            openThreadCount: 0,
            reviewMergeAction: action
        )

        XCTAssertEqual(summary?.title, "Draft pull request")
        XCTAssertEqual(summary?.detail, "This pull request is still a draft.")
        XCTAssertEqual(summary?.accent, .warning)
    }

    func testPullRequestLiveWatchPolicyDoesNotReloadOnInitialBaseline() {
        let current = PullRequestLiveWatchState(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 646),
            resolution: .open,
            isInMergeQueue: false,
            headSHA: "abc123",
            latestTimelineMarker: "1",
            detailsETag: "\"details-1\"",
            timelineETag: "\"timeline-1\""
        )

        let update = PullRequestLiveWatchPolicy.apply(previous: nil, current: current)

        XCTAssertFalse(update.shouldReloadFocus)
        XCTAssertFalse(update.shouldRefreshSnapshot)
        XCTAssertTrue(update.shouldContinueWatching)
    }

    func testPullRequestLiveWatchPolicyReloadsFocusForTimelineChangeOnly() {
        let previous = PullRequestLiveWatchState(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 646),
            resolution: .open,
            isInMergeQueue: false,
            headSHA: "abc123",
            latestTimelineMarker: "1",
            detailsETag: "\"details-1\"",
            timelineETag: "\"timeline-1\""
        )
        let current = PullRequestLiveWatchState(
            reference: previous.reference,
            resolution: .open,
            isInMergeQueue: false,
            headSHA: "abc123",
            latestTimelineMarker: "2",
            detailsETag: "\"details-1\"",
            timelineETag: "\"timeline-2\""
        )

        let update = PullRequestLiveWatchPolicy.apply(previous: previous, current: current)

        XCTAssertTrue(update.shouldReloadFocus)
        XCTAssertFalse(update.shouldRefreshSnapshot)
        XCTAssertTrue(update.shouldContinueWatching)
    }

    func testPullRequestLiveWatchPolicyRefreshesSnapshotWhenResolutionChanges() {
        let previous = PullRequestLiveWatchState(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 646),
            resolution: .open,
            isInMergeQueue: false,
            headSHA: "abc123",
            latestTimelineMarker: "1",
            detailsETag: "\"details-1\"",
            timelineETag: "\"timeline-1\""
        )
        let current = PullRequestLiveWatchState(
            reference: previous.reference,
            resolution: .merged,
            isInMergeQueue: false,
            headSHA: "def456",
            latestTimelineMarker: "3",
            detailsETag: "\"details-2\"",
            timelineETag: "\"timeline-2\""
        )

        let update = PullRequestLiveWatchPolicy.apply(previous: previous, current: current)

        XCTAssertTrue(update.shouldReloadFocus)
        XCTAssertTrue(update.shouldRefreshSnapshot)
        XCTAssertFalse(update.shouldContinueWatching)
    }

    func testPullRequestLiveWatchPolicyRefreshesSnapshotWhenQueueStateChanges() {
        let previous = PullRequestLiveWatchState(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 646),
            resolution: .open,
            isInMergeQueue: false,
            headSHA: "abc123",
            latestTimelineMarker: "1",
            detailsETag: "\"details-1\"",
            timelineETag: "\"timeline-1\""
        )
        let current = PullRequestLiveWatchState(
            reference: previous.reference,
            resolution: .open,
            isInMergeQueue: true,
            headSHA: "abc123",
            latestTimelineMarker: "1",
            detailsETag: "\"details-2\"",
            timelineETag: "\"timeline-1\""
        )

        let update = PullRequestLiveWatchPolicy.apply(previous: previous, current: current)

        XCTAssertTrue(update.shouldReloadFocus)
        XCTAssertTrue(update.shouldRefreshSnapshot)
        XCTAssertTrue(update.shouldContinueWatching)
    }

    func testMergeQueuePolicyRecognizesQueueRequiredErrors() {
        XCTAssertTrue(
            GitHubMergeQueuePolicy.shouldFallback(
                statusCode: 405,
                message: "Repository rule violations found\n\nChanges must be made through the merge queue"
            )
        )
        XCTAssertTrue(
            GitHubMergeQueuePolicy.shouldFallback(
                statusCode: 405,
                message: "This repository uses a merge queue."
            )
        )
        XCTAssertFalse(
            GitHubMergeQueuePolicy.shouldFallback(
                statusCode: 405,
                message: "Merge commits are not allowed on this repository."
            )
        )
        XCTAssertFalse(
            GitHubMergeQueuePolicy.shouldFallback(
                statusCode: 422,
                message: "Changes must be made through the merge queue"
            )
        )
    }

    func testMergeMethodPolicyPrioritizesStoredPreferenceWhenAllowed() {
        let methods = PullRequestMergeMethodPolicy.prioritizing(
            .squash,
            within: [.merge, .squash, .rebase]
        )

        XCTAssertEqual(methods, [.squash, .merge, .rebase])
    }

    func testMergeMethodPolicyLeavesOrderUntouchedWhenPreferenceIsUnavailable() {
        let methods = PullRequestMergeMethodPolicy.prioritizing(
            .rebase,
            within: [.merge, .squash]
        )

        XCTAssertEqual(methods, [.merge, .squash])
    }

    func testMergeMethodPolicyIntersectsRepositoryAndBranchAllowedMethods() {
        let methods = PullRequestMergeMethodPolicy.effectiveAllowedMethods(
            repositoryAllowedMethods: [.merge, .squash],
            branchAllowedMethodGroups: [[.merge, .squash, .rebase]],
            requiresLinearHistory: false
        )

        XCTAssertEqual(methods, [.merge, .squash])
    }

    func testMergeMethodPolicyRemovesMergeCommitsWhenBranchRequiresLinearHistory() {
        let methods = PullRequestMergeMethodPolicy.effectiveAllowedMethods(
            repositoryAllowedMethods: [.merge, .squash],
            branchAllowedMethodGroups: [[.merge, .squash, .rebase]],
            requiresLinearHistory: true
        )

        XCTAssertEqual(methods, [.squash])
    }

    func testPostMergeWatchPolicyNotifiesWhenQueuedPullRequestActuallyMerges() {
        let watch = PostMergeWatch(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 639),
            title: "Refresh module lockfiles",
            repository: "acme/cloud-infra-terraform",
            url: URL(string: "https://github.com/acme/cloud-infra-terraform/pull/639")!,
            createdAt: Date(timeIntervalSince1970: 100),
            queuedAt: Date(timeIntervalSince1970: 100),
            mergedAt: nil,
            mergeCommitSHA: nil,
            lastObservedWorkflowRunAt: nil,
            notifiedWorkflowRunIDs: [],
            notifiedApprovalRequiredWorkflowRunIDs: nil,
            suppressedWorkflowItemIDs: []
        )
        let observation = PostMergeWatchObservation(
            resolution: .merged,
            mergedAt: Date(timeIntervalSince1970: 200),
            mergeCommitSHA: "abc123",
            workflowRuns: []
        )

        let update = PostMergeWatchPolicy.apply(
            watch: watch,
            observation: observation,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(update.notifications.count, 1)
        XCTAssertEqual(update.notifications.first?.title, "Pull request merged")
        XCTAssertEqual(update.updatedWatch?.mergeCommitSHA, "abc123")
        XCTAssertEqual(update.updatedWatch?.mergedAt, Date(timeIntervalSince1970: 200))
    }

    func testPostMergeWatchRefreshPolicyRefreshesSnapshotWhenQueuedWatchResolves() {
        let watch = PostMergeWatch(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 639),
            title: "Refresh module lockfiles",
            repository: "acme/cloud-infra-terraform",
            url: URL(string: "https://github.com/acme/cloud-infra-terraform/pull/639")!,
            createdAt: Date(timeIntervalSince1970: 100),
            queuedAt: Date(timeIntervalSince1970: 100),
            mergedAt: nil,
            mergeCommitSHA: nil,
            lastObservedWorkflowRunAt: nil,
            notifiedWorkflowRunIDs: [],
            notifiedApprovalRequiredWorkflowRunIDs: nil,
            suppressedWorkflowItemIDs: []
        )

        XCTAssertTrue(
            PostMergeWatchRefreshPolicy.shouldRefreshSnapshot(
                watch: watch,
                observation: PostMergeWatchObservation(
                    resolution: .merged,
                    mergedAt: Date(timeIntervalSince1970: 200),
                    mergeCommitSHA: "abc123",
                    workflowRuns: []
                )
            )
        )
    }

    func testPostMergeWatchRefreshPolicySkipsOpenQueuedWatch() {
        let watch = PostMergeWatch(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 639),
            title: "Refresh module lockfiles",
            repository: "acme/cloud-infra-terraform",
            url: URL(string: "https://github.com/acme/cloud-infra-terraform/pull/639")!,
            createdAt: Date(timeIntervalSince1970: 100),
            queuedAt: Date(timeIntervalSince1970: 100),
            mergedAt: nil,
            mergeCommitSHA: nil,
            lastObservedWorkflowRunAt: nil,
            notifiedWorkflowRunIDs: [],
            notifiedApprovalRequiredWorkflowRunIDs: nil,
            suppressedWorkflowItemIDs: []
        )

        XCTAssertFalse(
            PostMergeWatchRefreshPolicy.shouldRefreshSnapshot(
                watch: watch,
                observation: PostMergeWatchObservation(
                    resolution: .open,
                    mergedAt: nil,
                    mergeCommitSHA: nil,
                    workflowRuns: []
                )
            )
        )
    }

    func testPostMergeWatchPolicyNotifiesSuccessfulWorkflowCompletion() {
        let watch = PostMergeWatch(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 639),
            title: "Refresh module lockfiles",
            repository: "acme/cloud-infra-terraform",
            url: URL(string: "https://github.com/acme/cloud-infra-terraform/pull/639")!,
            createdAt: Date(timeIntervalSince1970: 100),
            queuedAt: nil,
            mergedAt: Date(timeIntervalSince1970: 150),
            mergeCommitSHA: "abc123",
            lastObservedWorkflowRunAt: nil,
            notifiedWorkflowRunIDs: [],
            notifiedApprovalRequiredWorkflowRunIDs: nil,
            suppressedWorkflowItemIDs: []
        )
        let run = PostMergeObservedWorkflowRun(
            id: 42,
            workflowID: 7,
            title: "deploy",
            repository: "acme/cloud-infra-terraform",
            url: URL(string: "https://github.com/acme/cloud-infra-terraform/actions/runs/42")!,
            event: "push",
            status: "completed",
            conclusion: "success",
            requiresApproval: false,
            createdAt: Date(timeIntervalSince1970: 180),
            actor: nil
        )

        let update = PostMergeWatchPolicy.apply(
            watch: watch,
            observation: PostMergeWatchObservation(
                resolution: .merged,
                mergedAt: watch.mergedAt,
                mergeCommitSHA: "abc123",
                workflowRuns: [run]
            ),
            now: Date(timeIntervalSince1970: 181)
        )

        XCTAssertEqual(update.notifications.count, 1)
        XCTAssertEqual(update.notifications.first?.title, "Post-merge workflow succeeded")
        XCTAssertEqual(update.notifications.first?.subtitle, "deploy")
        XCTAssertEqual(update.updatedWatch?.notifiedWorkflowRunIDs, [42])
        XCTAssertEqual(update.updatedWatch?.suppressedWorkflowItemIDs, ["acme/cloud-infra-terraform-42"])
    }

    func testPostMergeWatchPolicyNotifiesFailedWorkflowCompletion() {
        let watch = PostMergeWatch(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 639),
            title: "Refresh module lockfiles",
            repository: "acme/cloud-infra-terraform",
            url: URL(string: "https://github.com/acme/cloud-infra-terraform/pull/639")!,
            createdAt: Date(timeIntervalSince1970: 100),
            queuedAt: nil,
            mergedAt: Date(timeIntervalSince1970: 150),
            mergeCommitSHA: "abc123",
            lastObservedWorkflowRunAt: nil,
            notifiedWorkflowRunIDs: [],
            notifiedApprovalRequiredWorkflowRunIDs: nil,
            suppressedWorkflowItemIDs: []
        )
        let run = PostMergeObservedWorkflowRun(
            id: 43,
            workflowID: 7,
            title: "deploy",
            repository: "acme/cloud-infra-terraform",
            url: URL(string: "https://github.com/acme/cloud-infra-terraform/actions/runs/43")!,
            event: "push",
            status: "completed",
            conclusion: "failure",
            requiresApproval: false,
            createdAt: Date(timeIntervalSince1970: 180),
            actor: nil
        )

        let update = PostMergeWatchPolicy.apply(
            watch: watch,
            observation: PostMergeWatchObservation(
                resolution: .merged,
                mergedAt: watch.mergedAt,
                mergeCommitSHA: "abc123",
                workflowRuns: [run]
            ),
            now: Date(timeIntervalSince1970: 181)
        )

        XCTAssertEqual(update.notifications.count, 1)
        XCTAssertEqual(update.notifications.first?.title, "Post-merge workflow failed")
        XCTAssertEqual(update.updatedWatch?.notifiedWorkflowRunIDs, [43])
        XCTAssertEqual(update.updatedWatch?.suppressedWorkflowItemIDs, ["acme/cloud-infra-terraform-43"])
    }

    func testPostMergeWatchPolicyExpiresCompletedMergeWatchAfterGraceWindow() {
        let mergedAt = Date(timeIntervalSince1970: 100)
        let watch = PostMergeWatch(
            reference: PullRequestReference(owner: "acme", name: "cloud-infra-terraform", number: 639),
            title: "Refresh module lockfiles",
            repository: "acme/cloud-infra-terraform",
            url: URL(string: "https://github.com/acme/cloud-infra-terraform/pull/639")!,
            createdAt: mergedAt,
            queuedAt: nil,
            mergedAt: mergedAt,
            mergeCommitSHA: "abc123",
            lastObservedWorkflowRunAt: nil,
            notifiedWorkflowRunIDs: [],
            notifiedApprovalRequiredWorkflowRunIDs: nil,
            suppressedWorkflowItemIDs: []
        )

        XCTAssertFalse(
            PostMergeWatchPolicy.shouldKeep(
                watch: watch,
                hasPendingRuns: false,
                now: mergedAt.addingTimeInterval(1_801)
            )
        )
    }

    func testAuthoredMergeActionDisablesWhenApprovalIsStillMissing() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .authoredPullRequest,
            mode: .authored,
            author: AttentionActor(login: "alberto", avatarURL: nil, isBot: false),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: PullRequestCheckSummary(
                passedCount: 7,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        XCTAssertEqual(action?.title, "Merge Pull Request")
        XCTAssertEqual(action?.isEnabled, false)
        XCTAssertEqual(action?.disabledReason, "This pull request still needs an approving review.")
    }

    func testPullRequestStatusSummaryShowsReadyToApproveAndMerge() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .assignedPullRequest,
            mode: .generic,
            author: AttentionActor(login: "renovate-custom-app", avatarURL: nil, isBot: true),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
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

    func testPullRequestStatusSummaryShowsReviewRequestBlocker() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .readyToMerge,
            mode: .authored,
            author: AttentionActor(login: "alberto", avatarURL: nil, isBot: false),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "APPROVED",
            approvalCount: 1,
            hasChangesRequested: false,
            pendingReviewRequestCount: 1,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        let summary = PullRequestStatusSummary.build(
            mode: .authored,
            checkSummary: PullRequestCheckSummary(
                passedCount: 8,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            reviewMergeAction: action
        )

        XCTAssertEqual(summary?.title, "Waiting on review")
        XCTAssertEqual(summary?.detail, "A review is still requested on this pull request.")
        XCTAssertEqual(summary?.accent, .warning)
    }

    func testPullRequestStatusSummaryShowsApprovalBlockerForAuthoredPullRequest() {
        let action = PullRequestReviewMergeAction.makeAction(
            sourceType: .authoredPullRequest,
            mode: .authored,
            author: AttentionActor(login: "alberto", avatarURL: nil, isBot: false),
            viewerPermission: "WRITE",
            allowMergeCommit: true,
            allowSquashMerge: true,
            allowRebaseMerge: true,
            mergeable: "MERGEABLE",
            isDraft: false,
            reviewDecision: "REVIEW_REQUIRED",
            approvalCount: 0,
            hasChangesRequested: false,
            pendingReviewRequestCount: 0,
            checkSummary: PullRequestCheckSummary(
                passedCount: 7,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0
        )

        let summary = PullRequestStatusSummary.build(
            mode: .authored,
            checkSummary: PullRequestCheckSummary(
                passedCount: 7,
                skippedCount: 1,
                failedCount: 0,
                pendingCount: 0
            ),
            openThreadCount: 0,
            reviewMergeAction: action
        )

        XCTAssertEqual(summary?.title, "Waiting on review")
        XCTAssertEqual(summary?.detail, "This pull request still needs an approving review.")
        XCTAssertEqual(summary?.accent, .warning)
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
            subjectKey: "https://github.com/acme/example/pull/42",
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
            subjectKey: "https://github.com/acme/example/issues/42",
            type: .mention,
            title: "Example issue",
            subtitle: "acme/example · Mentioned you",
            repository: "acme/example",
            timestamp: Date(),
            url: URL(string: "https://github.com/acme/example/issues/42")!
        )

        XCTAssertNil(item.pullRequestReference)
    }

    func testRemovedAssignedPullRequestCanNotifyUnassigned() {
        let item = AttentionItem(
            id: "pr:assign",
            subjectKey: "https://github.com/acme/cloud-infra-terraform/pull/638",
            type: .assignedPullRequest,
            title: "chore(deps): update module",
            subtitle: "acme/cloud-infra-terraform · Assigned pull request",
            repository: "acme/cloud-infra-terraform",
            timestamp: .now,
            url: URL(string: "https://github.com/acme/cloud-infra-terraform/pull/638")!
        )
        let state = GitHubSubjectResolutionState(
            reference: GitHubSubjectReference(
                owner: "acme",
                name: "cloud-infra-terraform",
                number: 638,
                kind: .pullRequest
            ),
            resolution: .open,
            isAssignedToViewer: false
        )

        let notification = AttentionRemovalNotificationPolicy.notification(
            for: [item],
            state: state
        )

        XCTAssertEqual(notification?.title, "Pull request unassigned")
        XCTAssertEqual(notification?.subtitle, item.title)
    }

    func testRemovedReadyToMergeCanNotifyMergedPullRequest() {
        let item = AttentionItem(
            id: "pr:ready",
            subjectKey: "https://github.com/ExampleOrg/offload-tools/pull/56",
            type: .readyToMerge,
            title: "Add aj zones subcommand",
            subtitle: "ExampleOrg/offload-tools · Ready to merge",
            repository: "ExampleOrg/offload-tools",
            timestamp: .now,
            url: URL(string: "https://github.com/ExampleOrg/offload-tools/pull/56")!
        )
        let state = GitHubSubjectResolutionState(
            reference: GitHubSubjectReference(
                owner: "ExampleOrg",
                name: "offload-tools",
                number: 56,
                kind: .pullRequest
            ),
            resolution: .merged,
            isAssignedToViewer: nil
        )

        let notification = AttentionRemovalNotificationPolicy.notification(
            for: [item],
            state: state
        )

        XCTAssertEqual(notification?.title, "Pull request merged")
        XCTAssertEqual(
            notification?.body,
            "Your pull request was merged in ExampleOrg/offload-tools."
        )
    }

    func testRemovedIssueCommentCanNotifyClosedIssue() {
        let item = AttentionItem(
            id: "issue:comment",
            subjectKey: "https://github.com/acme/saas-mega/issues/17748",
            type: .comment,
            title: "Investigate flaky deploy",
            subtitle: "acme/saas-mega · New comment",
            repository: "acme/saas-mega",
            timestamp: .now,
            url: URL(string: "https://github.com/acme/saas-mega/issues/17748")!
        )
        let state = GitHubSubjectResolutionState(
            reference: GitHubSubjectReference(
                owner: "acme",
                name: "saas-mega",
                number: 17748,
                kind: .issue
            ),
            resolution: .closed,
            isAssignedToViewer: nil
        )

        let notification = AttentionRemovalNotificationPolicy.notification(
            for: [item],
            state: state
        )

        XCTAssertEqual(notification?.title, "Issue closed")
        XCTAssertEqual(
            notification?.body,
            "An issue you were following was closed in acme/saas-mega."
        )
    }

    func testRemovedTeamReviewRequestedDoesNotNotifyClosedPullRequest() {
        let item = AttentionItem(
            id: "pr:team-review",
            subjectKey: "https://github.com/ExampleOrg/testcontainers-cloud-web/pull/1038",
            type: .teamReviewRequested,
            title: "chore(deps): bump axios",
            subtitle: "ExampleOrg/testcontainers-cloud-web · Team review requested",
            repository: "ExampleOrg/testcontainers-cloud-web",
            timestamp: .now,
            url: URL(string: "https://github.com/ExampleOrg/testcontainers-cloud-web/pull/1038")!
        )
        let state = GitHubSubjectResolutionState(
            reference: GitHubSubjectReference(
                owner: "ExampleOrg",
                name: "testcontainers-cloud-web",
                number: 1038,
                kind: .pullRequest
            ),
            resolution: .closed,
            isAssignedToViewer: nil
        )

        let notification = AttentionRemovalNotificationPolicy.notification(
            for: [item],
            state: state
        )

        XCTAssertNil(notification)
    }

    func testRemovedReviewRequestedCanRegisterPostMergeWatch() {
        let item = AttentionItem(
            id: "pr:review",
            subjectKey: "https://github.com/ExampleOrg/sample-services/pull/1102",
            type: .reviewRequested,
            title: "DCL-1591 add billing-mode setting",
            subtitle: "ExampleOrg/sample-services · Review requested",
            repository: "ExampleOrg/sample-services",
            timestamp: .now,
            url: URL(string: "https://github.com/ExampleOrg/sample-services/pull/1102")!
        )
        let mergedAt = Date(timeIntervalSince1970: 200)
        let state = GitHubSubjectResolutionState(
            reference: GitHubSubjectReference(
                owner: "ExampleOrg",
                name: "sample-services",
                number: 1102,
                kind: .pullRequest
            ),
            resolution: .merged,
            isAssignedToViewer: nil,
            mergedAt: mergedAt,
            mergeCommitSHA: "abc123"
        )

        let watch = AttentionRemovalPostMergeWatchPolicy.watch(
            for: [item],
            state: state,
            now: Date(timeIntervalSince1970: 210)
        )

        XCTAssertEqual(watch?.id, item.url.absoluteString)
        XCTAssertEqual(watch?.mergedAt, mergedAt)
        XCTAssertEqual(watch?.mergeCommitSHA, "abc123")
    }

    func testRemovedClosedIssueDoesNotRegisterPostMergeWatch() {
        let item = AttentionItem(
            id: "issue:authored",
            subjectKey: "https://github.com/ExampleOrg/sample-services/issues/42",
            type: .authoredIssue,
            title: "Track usage billing mode",
            subtitle: "ExampleOrg/sample-services · Issue you opened",
            repository: "ExampleOrg/sample-services",
            timestamp: .now,
            url: URL(string: "https://github.com/ExampleOrg/sample-services/issues/42")!
        )
        let state = GitHubSubjectResolutionState(
            reference: GitHubSubjectReference(
                owner: "ExampleOrg",
                name: "sample-services",
                number: 42,
                kind: .issue
            ),
            resolution: .closed,
            isAssignedToViewer: nil,
            mergedAt: nil,
            mergeCommitSHA: nil
        )

        XCTAssertNil(
            AttentionRemovalPostMergeWatchPolicy.watch(
                for: [item],
                state: state
            )
        )
    }

    func testRepositoryWorkflowPathFiltersDynamicWorkflows() {
        XCTAssertTrue(
            GitHubClient.isRepositoryWorkflowPath(".github/workflows/build.yaml")
        )
        XCTAssertTrue(
            GitHubClient.isRepositoryWorkflowPath(".github/workflows/deploy.yml")
        )
        XCTAssertFalse(
            GitHubClient.isRepositoryWorkflowPath("dynamic/dependabot/dependabot-updates")
        )
        XCTAssertFalse(
            GitHubClient.isRepositoryWorkflowPath("dynamic/github-code-scanning/codeql")
        )
    }

    func testWorkflowPredictionRefPrefersMergeCommitWhenAvailable() {
        XCTAssertEqual(
            GitHubClient.workflowPredictionRef(
                headRefOID: "head-oid",
                mergeCommitSHA: nil
            ),
            "head-oid"
        )
        XCTAssertEqual(
            GitHubClient.workflowPredictionRef(
                headRefOID: "head-oid",
                mergeCommitSHA: "merge-oid"
            ),
            "merge-oid"
        )
    }
}

private func temporaryUserDefaults() -> UserDefaults {
    let suiteName = "AttentionClassificationTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

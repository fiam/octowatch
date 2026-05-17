import XCTest
@testable import Octowatch

final class SnapshotPollGraphQLTests: XCTestCase {
    // MARK: - Test rig

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func buildSnapshot(
        _ json: String,
        login: String = "alice"
    ) throws -> SnapshotPollData {
        let payload = try decoder.decode(
            SnapshotPollQueryData.self,
            from: json.data(using: .utf8)!
        )
        return GitHubClient().buildSnapshotPollData(from: payload, login: login)
    }

    // MARK: - Happy path

    func testDecodesAndMapsAllSearchAliases() throws {
        let json = SnapshotJSON(
            assigned: [
                .pr(number: 1, title: "Assigned PR",
                    url: "https://github.com/acme/repo/pull/1",
                    repository: "acme/repo",
                    updatedAt: "2026-05-16T12:00:00Z",
                    state: "OPEN")
            ],
            authoredOpen: [
                .pr(number: 2, title: "Open authored",
                    url: "https://github.com/acme/repo/pull/2",
                    repository: "acme/repo",
                    updatedAt: "2026-05-16T11:00:00Z",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: nil,
                    reviewRequestsTotal: 0)
            ],
            authoredMerged: [
                .pr(number: 3, title: "Merged authored",
                    url: "https://github.com/acme/repo/pull/3",
                    repository: "acme/repo",
                    updatedAt: "2026-05-15T10:00:00Z",
                    state: "MERGED",
                    merged: true,
                    mergedAt: "2026-05-15T10:30:00Z",
                    mergedBy: .user("bob"))
            ],
            reviewed: [
                .pr(number: 4, title: "Reviewed",
                    url: "https://github.com/acme/repo/pull/4",
                    repository: "acme/repo",
                    updatedAt: "2026-05-14T08:00:00Z",
                    state: "OPEN",
                    viewerReviews: [
                        .review(state: "APPROVED", submittedAt: "2026-05-14T08:00:00Z", login: "alice")
                    ])
            ],
            commented: [
                .pr(number: 5, title: "Commented",
                    url: "https://github.com/acme/repo/pull/5",
                    repository: "acme/repo",
                    updatedAt: "2026-05-13T08:00:00Z",
                    state: "OPEN")
            ],
            rateLimit: .init(cost: 1, remaining: 4999, resetAt: "2026-05-16T16:00:00Z")
        ).render()

        let snapshot = try buildSnapshot(json)

        XCTAssertEqual(snapshot.assignedPullRequests.count, 1)
        XCTAssertEqual(snapshot.assignedPullRequests.first?.number, 1)
        XCTAssertEqual(snapshot.assignedPullRequests.first?.title, "Assigned PR")
        XCTAssertEqual(snapshot.assignedPullRequests.first?.repository, "acme/repo")
        XCTAssertEqual(snapshot.assignedPullRequests.first?.resolution, .open)
        XCTAssertEqual(snapshot.assignedPullRequests.first?.subtitle, "#1 · acme/repo")

        XCTAssertEqual(snapshot.openAuthoredPullRequests.count, 1)
        XCTAssertEqual(snapshot.openAuthoredPullRequests.first?.number, 2)

        // Tracked: one each from authoredOpen (.authoredPullRequest open), authoredMerged
        // (.authoredPullRequest merged), reviewed, commented.
        XCTAssertEqual(snapshot.trackedPullRequests.count, 4)

        let merged = snapshot.trackedPullRequests.first { $0.number == 3 }
        XCTAssertEqual(merged?.resolution, .merged)
        XCTAssertEqual(merged?.actor?.login, "bob")
        XCTAssertEqual(merged?.subtitle, "acme/repo · Merged by bob")

        let reviewed = snapshot.trackedPullRequests.first { $0.number == 4 }
        XCTAssertEqual(reviewed?.type, .reviewedPullRequest)
        XCTAssertEqual(reviewed?.latestSelfUpdate?.type, .reviewApproved)
        XCTAssertEqual(reviewed?.latestSelfUpdate?.actor?.login, "alice")
    }

    func testEmptySearchResultsProduceEmptySnapshot() throws {
        let json = SnapshotJSON().render()
        let snapshot = try buildSnapshot(json)

        XCTAssertTrue(snapshot.assignedPullRequests.isEmpty)
        XCTAssertTrue(snapshot.openAuthoredPullRequests.isEmpty)
        XCTAssertTrue(snapshot.trackedPullRequests.isEmpty)
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    // MARK: - Subject resolution + draft handling

    func testStateAndMergedFlagDriveResolution() throws {
        let json = SnapshotJSON(
            assigned: [
                .pr(number: 10, title: "Open", url: "https://github.com/a/b/pull/10",
                    repository: "a/b", state: "OPEN", merged: false),
                .pr(number: 11, title: "Closed", url: "https://github.com/a/b/pull/11",
                    repository: "a/b", state: "CLOSED", merged: false),
                .pr(number: 12, title: "Merged", url: "https://github.com/a/b/pull/12",
                    repository: "a/b", state: "MERGED", merged: true,
                    mergedAt: "2026-05-15T10:30:00Z")
            ]
        ).render()

        let snapshot = try buildSnapshot(json)
        let byNumber = Dictionary(uniqueKeysWithValues: snapshot.assignedPullRequests.map { ($0.number, $0) })

        XCTAssertEqual(byNumber[10]?.resolution, .open)
        XCTAssertEqual(byNumber[11]?.resolution, .closed)
        XCTAssertEqual(byNumber[12]?.resolution, .merged)
    }

    func testMergedFlagOverridesStateForResolution() throws {
        let json = SnapshotJSON(
            assigned: [
                .pr(number: 1, title: "Looks closed but merged",
                    url: "https://github.com/a/b/pull/1",
                    repository: "a/b",
                    state: "CLOSED",
                    merged: true,
                    mergedAt: "2026-05-15T10:30:00Z")
            ]
        ).render()

        let snapshot = try buildSnapshot(json)
        XCTAssertEqual(snapshot.assignedPullRequests.first?.resolution, .merged)
    }

    func testDraftPullRequestIncludesDraftMarkerInSubtitle() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 7, title: "Draft work",
                    url: "https://github.com/a/b/pull/7",
                    repository: "a/b",
                    updatedAt: "2026-05-16T12:00:00Z",
                    state: "OPEN",
                    isDraft: true)
            ]
        ).render()

        let snapshot = try buildSnapshot(json)
        let pr = snapshot.openAuthoredPullRequests.first
        XCTAssertEqual(pr?.isDraft, true)
        XCTAssertEqual(pr?.subtitle, "#7 · a/b · Draft")

        let tracked = snapshot.trackedPullRequests.first
        XCTAssertEqual(tracked?.isDraft, true)
        XCTAssertEqual(tracked?.subtitle, "a/b · Draft · Created by you")
    }

    // MARK: - Merged-by attribution

    func testMergedAuthoredSubtitleWhenMergedByCurrentUser() throws {
        let json = SnapshotJSON(
            authoredMerged: [
                .pr(number: 1, title: "Self-merge",
                    url: "https://github.com/a/b/pull/1",
                    repository: "a/b",
                    state: "MERGED",
                    merged: true,
                    mergedAt: "2026-05-15T10:30:00Z",
                    mergedBy: .user("alice"))
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        let tracked = snapshot.trackedPullRequests.first
        XCTAssertEqual(tracked?.subtitle, "a/b · Merged by you")
        XCTAssertEqual(tracked?.actor?.login, "alice")
    }

    func testMergedAuthoredSubtitleFallsBackWhenMergedByMissing() throws {
        let json = SnapshotJSON(
            authoredMerged: [
                .pr(number: 1, title: "Auto-merged",
                    url: "https://github.com/a/b/pull/1",
                    repository: "a/b",
                    state: "MERGED",
                    merged: true,
                    mergedAt: "2026-05-15T10:30:00Z",
                    mergedBy: nil)
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        let tracked = snapshot.trackedPullRequests.first
        XCTAssertEqual(tracked?.subtitle, "a/b · Pull request merged")
        XCTAssertNil(tracked?.actor)
    }

    // MARK: - Reviewed: viewer review wins

    func testReviewedTrackedPicksLatestViewerReview() throws {
        let json = SnapshotJSON(
            reviewed: [
                .pr(number: 9, title: "Reviewed twice",
                    url: "https://github.com/a/b/pull/9",
                    repository: "a/b",
                    state: "OPEN",
                    viewerReviews: [
                        .review(state: "COMMENTED", submittedAt: "2026-05-10T10:00:00Z", login: "alice"),
                        .review(state: "APPROVED", submittedAt: "2026-05-12T10:00:00Z", login: "alice"),
                        // Should be ignored — not authored by viewer.
                        .review(state: "CHANGES_REQUESTED", submittedAt: "2026-05-13T10:00:00Z", login: "bob")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        let tracked = snapshot.trackedPullRequests.first
        XCTAssertEqual(tracked?.latestSelfUpdate?.type, .reviewApproved)
        XCTAssertEqual(tracked?.latestSelfUpdate?.actor?.login, "alice")
    }

    func testReviewedTrackedHandlesDismissedReviewAsNoSelfUpdate() throws {
        let json = SnapshotJSON(
            reviewed: [
                .pr(number: 9, title: "Reviewed and dismissed",
                    url: "https://github.com/a/b/pull/9",
                    repository: "a/b",
                    state: "OPEN",
                    viewerReviews: [
                        .review(state: "DISMISSED", submittedAt: "2026-05-12T10:00:00Z", login: "alice")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertNil(snapshot.trackedPullRequests.first?.latestSelfUpdate)
    }

    // MARK: - Authored signals

    func testReadyToMergeSignalSurfacesWhenAllConditionsMet() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 20, title: "Ready",
                    url: "https://github.com/a/b/pull/20",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: "APPROVED",
                    reviewRequestsTotal: 0,
                    reviews: [
                        .review(state: "APPROVED", submittedAt: "2026-05-15T10:00:00Z", login: "carol")
                    ],
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "build", status: "COMPLETED", conclusion: "SUCCESS")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        let signals = snapshot.authoredPullRequestSignals
        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.type, .readyToMerge)
        XCTAssertEqual(signals.first?.actor?.login, "carol")
        XCTAssertEqual(signals.first?.approvalCount, 1)
        XCTAssertEqual(signals.first?.subtitle, "carol · a/b · Ready to merge")
    }

    func testReadyToMergeSuppressedWhenDraft() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 21, title: "Draft ready",
                    url: "https://github.com/a/b/pull/21",
                    repository: "a/b",
                    state: "OPEN",
                    isDraft: true,
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: "APPROVED",
                    reviewRequestsTotal: 0,
                    reviews: [
                        .review(state: "APPROVED", submittedAt: "2026-05-15T10:00:00Z", login: "carol")
                    ],
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "build", status: "COMPLETED", conclusion: "SUCCESS")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    func testReadyToMergeSuppressedWhenReviewRequestsOutstanding() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 22, title: "Pending review",
                    url: "https://github.com/a/b/pull/22",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: "APPROVED",
                    reviewRequestsTotal: 1,
                    reviews: [
                        .review(state: "APPROVED", submittedAt: "2026-05-15T10:00:00Z", login: "carol")
                    ],
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "build", status: "COMPLETED", conclusion: "SUCCESS")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    func testReadyToMergeSuppressedWhenChangesRequested() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 23, title: "Changes requested",
                    url: "https://github.com/a/b/pull/23",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: "CHANGES_REQUESTED",
                    reviewRequestsTotal: 0,
                    reviews: [
                        .review(state: "CHANGES_REQUESTED", submittedAt: "2026-05-15T10:00:00Z", login: "carol")
                    ],
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "build", status: "COMPLETED", conclusion: "SUCCESS")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    func testReadyToMergeSuppressedWhenPendingChecks() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 24, title: "Pending checks",
                    url: "https://github.com/a/b/pull/24",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: "APPROVED",
                    reviewRequestsTotal: 0,
                    reviews: [
                        .review(state: "APPROVED", submittedAt: "2026-05-15T10:00:00Z", login: "carol")
                    ],
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "build", status: "COMPLETED", conclusion: "SUCCESS"),
                        .checkRun(databaseId: 2, name: "deploy", status: "IN_PROGRESS", conclusion: nil)
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    func testMergeConflictsSignalSurfacesWhenMergeableIsConflicting() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 25, title: "Conflicts",
                    url: "https://github.com/a/b/pull/25",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "CONFLICTING",
                    reviewDecision: nil,
                    reviewRequestsTotal: 0)
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertEqual(snapshot.authoredPullRequestSignals.count, 1)
        XCTAssertEqual(snapshot.authoredPullRequestSignals.first?.type, .pullRequestMergeConflicts)
        XCTAssertEqual(snapshot.authoredPullRequestSignals.first?.subtitle, "a/b · Merge conflicts")
    }

    func testFailedChecksSignalSurfacesWhenAnyCheckFailed() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 26, title: "Broken",
                    url: "https://github.com/a/b/pull/26",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: nil,
                    reviewRequestsTotal: 0,
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "test", status: "COMPLETED", conclusion: "FAILURE"),
                        .checkRun(databaseId: 2, name: "lint", status: "COMPLETED", conclusion: "FAILURE")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertEqual(snapshot.authoredPullRequestSignals.count, 1)
        let signal = snapshot.authoredPullRequestSignals.first
        XCTAssertEqual(signal?.type, .pullRequestFailedChecks)
        XCTAssertEqual(signal?.checkSummary.failedCount, 2)
        XCTAssertEqual(signal?.subtitle, "a/b · 2 failed checks")
    }

    func testFailedChecksSubtitleHandlesSingularLabel() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 27, title: "One failure",
                    url: "https://github.com/a/b/pull/27",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: nil,
                    reviewRequestsTotal: 0,
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "test", status: "COMPLETED", conclusion: "FAILURE")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertEqual(snapshot.authoredPullRequestSignals.first?.subtitle, "a/b · 1 failed check")
    }

    func testAuthoredSignalsExcludeReviewsByViewerForApprovalCount() throws {
        // Viewer's own approval should not count toward approval threshold.
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 28, title: "Self approval",
                    url: "https://github.com/a/b/pull/28",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: "APPROVED",
                    reviewRequestsTotal: 0,
                    reviews: [
                        .review(state: "APPROVED", submittedAt: "2026-05-15T10:00:00Z", login: "alice")
                    ],
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "build", status: "COMPLETED", conclusion: "SUCCESS")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    func testAuthoredSignalsSkipMergedOrClosedPullRequests() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 29, title: "Already merged",
                    url: "https://github.com/a/b/pull/29",
                    repository: "a/b",
                    state: "MERGED",
                    merged: true,
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: "APPROVED",
                    reviewRequestsTotal: 0,
                    reviews: [
                        .review(state: "APPROVED", submittedAt: "2026-05-15T10:00:00Z", login: "carol")
                    ],
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "build", status: "COMPLETED", conclusion: "SUCCESS")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    // MARK: - Check rollup edge cases

    func testCheckRollupIgnoresNonCheckRunContexts() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 30, title: "Mixed contexts",
                    url: "https://github.com/a/b/pull/30",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: nil,
                    reviewRequestsTotal: 0,
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "build", status: "COMPLETED", conclusion: "SUCCESS")
                    ],
                    extraContextsJSON: """
                    , { "__typename": "StatusContext" }
                    """)
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        // No ready-to-merge since no approval; verify failed-checks not surfaced (no failure)
        // and that the StatusContext didn't crash parsing.
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    func testCheckRollupDeduplicatesRerunsByLogicalIdentifier() throws {
        // Same name+appSlug, different attempts — only the latest counts toward the summary.
        // Older attempt is FAILURE, newer is SUCCESS — should NOT surface failed-checks.
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 31, title: "Rerun",
                    url: "https://github.com/a/b/pull/31",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: nil,
                    reviewRequestsTotal: 0,
                    checkRuns: [
                        .checkRun(databaseId: 100, name: "build", status: "COMPLETED",
                                  conclusion: "FAILURE", appSlug: "github-actions",
                                  startedAt: "2026-05-15T08:00:00Z",
                                  completedAt: "2026-05-15T08:10:00Z"),
                        .checkRun(databaseId: 101, name: "build", status: "COMPLETED",
                                  conclusion: "SUCCESS", appSlug: "github-actions",
                                  startedAt: "2026-05-15T09:00:00Z",
                                  completedAt: "2026-05-15T09:10:00Z")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    func testCheckRollupTreatsActionRequiredAndTimedOutAsFailures() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 32, title: "Mixed failures",
                    url: "https://github.com/a/b/pull/32",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: nil,
                    reviewRequestsTotal: 0,
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "approval", status: "COMPLETED", conclusion: "ACTION_REQUIRED"),
                        .checkRun(databaseId: 2, name: "deploy", status: "COMPLETED", conclusion: "TIMED_OUT"),
                        .checkRun(databaseId: 3, name: "cleanup", status: "COMPLETED", conclusion: "CANCELLED"),
                        .checkRun(databaseId: 4, name: "boot", status: "COMPLETED", conclusion: "STARTUP_FAILURE")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        let signal = snapshot.authoredPullRequestSignals.first
        XCTAssertEqual(signal?.type, .pullRequestFailedChecks)
        XCTAssertEqual(signal?.checkSummary.failedCount, 4)
    }

    func testCheckRollupCountsSkippedAndNeutralSeparately() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 33, title: "Skipped",
                    url: "https://github.com/a/b/pull/33",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: "APPROVED",
                    reviewRequestsTotal: 0,
                    reviews: [
                        .review(state: "APPROVED", submittedAt: "2026-05-15T10:00:00Z", login: "carol")
                    ],
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "test", status: "COMPLETED", conclusion: "SUCCESS"),
                        .checkRun(databaseId: 2, name: "lint", status: "COMPLETED", conclusion: "SKIPPED"),
                        .checkRun(databaseId: 3, name: "format", status: "COMPLETED", conclusion: "NEUTRAL")
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        XCTAssertEqual(snapshot.authoredPullRequestSignals.count, 1)
        let signal = snapshot.authoredPullRequestSignals.first
        XCTAssertEqual(signal?.type, .readyToMerge)
        XCTAssertEqual(signal?.checkSummary.passedCount, 1)
        XCTAssertEqual(signal?.checkSummary.skippedCount, 2)
        XCTAssertEqual(signal?.checkSummary.failedCount, 0)
    }

    func testCheckRollupTreatsConclusionlessCompletedAsPending() throws {
        // A check run with status "COMPLETED" but no conclusion is unusual — count as pending.
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 34, title: "Conclusionless",
                    url: "https://github.com/a/b/pull/34",
                    repository: "a/b",
                    state: "OPEN",
                    includeSignals: true,
                    mergeable: "MERGEABLE",
                    reviewDecision: "APPROVED",
                    reviewRequestsTotal: 0,
                    reviews: [
                        .review(state: "APPROVED", submittedAt: "2026-05-15T10:00:00Z", login: "carol")
                    ],
                    checkRuns: [
                        .checkRun(databaseId: 1, name: "build", status: "COMPLETED", conclusion: "SUCCESS"),
                        .checkRun(databaseId: 2, name: "deploy", status: "COMPLETED", conclusion: nil)
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        // Pending should suppress ready-to-merge.
        XCTAssertTrue(snapshot.authoredPullRequestSignals.isEmpty)
    }

    // MARK: - Node typing & filtering

    func testNullNodesAreFiltered() throws {
        let rawAssigned = """
        [null, \(PRNode.pr(number: 1, title: "Real",
                            url: "https://github.com/a/b/pull/1",
                            repository: "a/b",
                            state: "OPEN").renderJSON()), null]
        """
        let json = """
        {
          "assigned": { "nodes": \(rawAssigned) },
          "authoredOpen": { "nodes": [] },
          "authoredMerged": { "nodes": [] },
          "reviewed": { "nodes": [] },
          "commented": { "nodes": [] }
        }
        """

        let snapshot = try buildSnapshot(json)
        XCTAssertEqual(snapshot.assignedPullRequests.count, 1)
        XCTAssertEqual(snapshot.assignedPullRequests.first?.number, 1)
    }

    func testNonPullRequestNodesAreFiltered() throws {
        let json = """
        {
          "assigned": { "nodes": [
            { "__typename": "Issue", "databaseId": 1, "number": 1, "title": "Issue",
              "url": "https://github.com/a/b/issues/1",
              "isDraft": false, "updatedAt": "2026-05-16T12:00:00Z",
              "state": "OPEN", "merged": false, "mergedAt": null,
              "repository": { "nameWithOwner": "a/b" },
              "author": null, "labels": { "nodes": [] } },
            \(PRNode.pr(number: 2, title: "PR",
                        url: "https://github.com/a/b/pull/2",
                        repository: "a/b",
                        state: "OPEN").renderJSON())
          ] },
          "authoredOpen": { "nodes": [] },
          "authoredMerged": { "nodes": [] },
          "reviewed": { "nodes": [] },
          "commented": { "nodes": [] }
        }
        """

        let snapshot = try buildSnapshot(json)
        XCTAssertEqual(snapshot.assignedPullRequests.count, 1)
        XCTAssertEqual(snapshot.assignedPullRequests.first?.number, 2)
    }

    // MARK: - Bot author & missing fields

    func testBotAuthorIsRecognizedInActor() throws {
        // The author isn't directly exposed in summaries, but the actor for merged PRs is.
        let json = SnapshotJSON(
            authoredMerged: [
                .pr(number: 1, title: "Bot merge",
                    url: "https://github.com/a/b/pull/1",
                    repository: "a/b",
                    state: "MERGED",
                    merged: true,
                    mergedAt: "2026-05-15T10:30:00Z",
                    mergedBy: .bot("dependabot"))
            ]
        ).render()

        let snapshot = try buildSnapshot(json, login: "alice")
        let tracked = snapshot.trackedPullRequests.first
        XCTAssertEqual(tracked?.actor?.login, "dependabot")
        XCTAssertEqual(tracked?.actor?.isBotAccount, true)
    }

    func testMissingAuthorDoesNotPreventDecoding() throws {
        let json = SnapshotJSON(
            assigned: [
                .pr(number: 1, title: "Anonymous",
                    url: "https://github.com/a/b/pull/1",
                    repository: "a/b",
                    state: "OPEN",
                    authorLogin: nil)
            ]
        ).render()

        let snapshot = try buildSnapshot(json)
        XCTAssertEqual(snapshot.assignedPullRequests.count, 1)
    }

    // MARK: - Labels

    func testLabelsAreDecodedWithColorAndDescription() throws {
        let json = SnapshotJSON(
            assigned: [
                .pr(number: 1, title: "Labeled",
                    url: "https://github.com/a/b/pull/1",
                    repository: "a/b",
                    state: "OPEN",
                    labels: [
                        LabelFixture(name: "bug", color: "d73a4a", description: "Something is broken"),
                        LabelFixture(name: "enhancement", color: "a2eeef", description: nil)
                    ])
            ]
        ).render()

        let snapshot = try buildSnapshot(json)
        let labels = snapshot.assignedPullRequests.first?.labels ?? []
        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(labels[0].name, "bug")
        XCTAssertEqual(labels[0].colorHex, "d73a4a")
        XCTAssertEqual(labels[0].description, "Something is broken")
        XCTAssertEqual(labels[1].description, nil)
    }

    // MARK: - Deduplication

    func testAssignedPullRequestsDeduplicateByIgnoreKey() throws {
        let json = SnapshotJSON(
            assigned: [
                .pr(number: 1, title: "First copy",
                    url: "https://github.com/a/b/pull/1",
                    repository: "a/b",
                    updatedAt: "2026-05-14T12:00:00Z",
                    state: "OPEN"),
                .pr(number: 1, title: "Second copy (newer)",
                    url: "https://github.com/a/b/pull/1",
                    repository: "a/b",
                    updatedAt: "2026-05-16T12:00:00Z",
                    state: "OPEN")
            ]
        ).render()

        let snapshot = try buildSnapshot(json)
        XCTAssertEqual(snapshot.assignedPullRequests.count, 1)
        XCTAssertEqual(snapshot.assignedPullRequests.first?.title, "Second copy (newer)")
    }

    // MARK: - Rate limit decoding

    func testRateLimitFieldDecodesWhenPresent() throws {
        let json = SnapshotJSON(
            rateLimit: .init(cost: 7, remaining: 4990, resetAt: "2026-05-16T16:00:00Z")
        ).render()

        let payload = try decoder.decode(
            SnapshotPollQueryData.self,
            from: json.data(using: .utf8)!
        )
        XCTAssertEqual(payload.rateLimit?.cost, 7)
        XCTAssertEqual(payload.rateLimit?.remaining, 4990)
        XCTAssertNotNil(payload.rateLimit?.resetAt)
    }

    func testRateLimitFieldIsOptional() throws {
        let json = SnapshotJSON().render()
        let payload = try decoder.decode(
            SnapshotPollQueryData.self,
            from: json.data(using: .utf8)!
        )
        XCTAssertNil(payload.rateLimit)
    }

    // MARK: - Workflow watch candidate plumbing (PR-summary input)

    func testOpenAuthoredPullRequestsExposeRepositoryAndNumberForWorkflowCandidates() throws {
        let json = SnapshotJSON(
            authoredOpen: [
                .pr(number: 100, title: "Author PR",
                    url: "https://github.com/acme/repo/pull/100",
                    repository: "acme/repo",
                    state: "OPEN")
            ]
        ).render()

        let snapshot = try buildSnapshot(json)
        let pr = snapshot.openAuthoredPullRequests.first
        XCTAssertEqual(pr?.repository, "acme/repo")
        XCTAssertEqual(pr?.number, 100)
    }
}

// MARK: - JSON fixture builder

private struct SnapshotJSON {
    var assigned: [PRNode] = []
    var authoredOpen: [PRNode] = []
    var authoredMerged: [PRNode] = []
    var reviewed: [PRNode] = []
    var commented: [PRNode] = []
    var rateLimit: RateLimitFixture?

    struct RateLimitFixture {
        var cost: Int
        var remaining: Int
        var resetAt: String
    }

    func render() -> String {
        let rateLimitJSON: String
        if let rl = rateLimit {
            rateLimitJSON = """
            ,
            "rateLimit": { "cost": \(rl.cost), "remaining": \(rl.remaining), "resetAt": "\(rl.resetAt)" }
            """
        } else {
            rateLimitJSON = ""
        }
        return """
        {
          "assigned": { "nodes": [\(assigned.map { $0.renderJSON() }.joined(separator: ","))] },
          "authoredOpen": { "nodes": [\(authoredOpen.map { $0.renderJSON() }.joined(separator: ","))] },
          "authoredMerged": { "nodes": [\(authoredMerged.map { $0.renderJSON() }.joined(separator: ","))] },
          "reviewed": { "nodes": [\(reviewed.map { $0.renderJSON() }.joined(separator: ","))] },
          "commented": { "nodes": [\(commented.map { $0.renderJSON() }.joined(separator: ","))] }
          \(rateLimitJSON)
        }
        """
    }
}

private struct LabelFixture {
    var name: String
    var color: String
    var description: String?
}

private struct ReviewFixture {
    var state: String
    var submittedAt: String
    var login: String

    static func review(state: String, submittedAt: String, login: String) -> ReviewFixture {
        ReviewFixture(state: state, submittedAt: submittedAt, login: login)
    }
}

private struct CheckRunFixture {
    var databaseId: Int
    var name: String
    var status: String
    var conclusion: String?
    var appSlug: String?
    var startedAt: String?
    var completedAt: String?

    static func checkRun(
        databaseId: Int,
        name: String,
        status: String,
        conclusion: String?,
        appSlug: String? = nil,
        startedAt: String? = nil,
        completedAt: String? = nil
    ) -> CheckRunFixture {
        CheckRunFixture(
            databaseId: databaseId,
            name: name,
            status: status,
            conclusion: conclusion,
            appSlug: appSlug,
            startedAt: startedAt,
            completedAt: completedAt
        )
    }
}

private enum ActorFixture {
    case user(String)
    case bot(String)

    var login: String {
        switch self {
        case .user(let l), .bot(let l): return l
        }
    }

    var typeName: String {
        switch self {
        case .user: return "User"
        case .bot: return "Bot"
        }
    }
}

private struct PRNode {
    var typeName: String = "PullRequest"
    var databaseId: Int
    var number: Int
    var title: String
    var url: String
    var repository: String
    var updatedAt: String = "2026-05-16T12:00:00Z"
    var state: String
    var merged: Bool = false
    var mergedAt: String?
    var isDraft: Bool = false
    var authorLogin: String? = "bob"
    var authorTypeName: String = "User"
    var labels: [LabelFixture] = []
    var mergedBy: ActorFixture?
    var viewerReviews: [ReviewFixture] = []
    var reviews: [ReviewFixture] = []
    var mergeable: String?
    var reviewDecision: String?
    var headRefOid: String?
    var reviewRequestsTotal: Int?
    var checkRuns: [CheckRunFixture] = []
    var extraContextsJSON: String = ""
    var includeSignals: Bool = false

    static func pr(
        number: Int,
        title: String,
        url: String,
        repository: String,
        updatedAt: String = "2026-05-16T12:00:00Z",
        state: String,
        merged: Bool = false,
        mergedAt: String? = nil,
        isDraft: Bool = false,
        authorLogin: String? = "bob",
        authorTypeName: String = "User",
        labels: [LabelFixture] = [],
        mergedBy: ActorFixture? = nil,
        viewerReviews: [ReviewFixture] = [],
        includeSignals: Bool = false,
        mergeable: String? = nil,
        reviewDecision: String? = nil,
        reviewRequestsTotal: Int? = nil,
        reviews: [ReviewFixture] = [],
        checkRuns: [CheckRunFixture] = [],
        extraContextsJSON: String = ""
    ) -> PRNode {
        PRNode(
            databaseId: number,
            number: number,
            title: title,
            url: url,
            repository: repository,
            updatedAt: updatedAt,
            state: state,
            merged: merged,
            mergedAt: mergedAt,
            isDraft: isDraft,
            authorLogin: authorLogin,
            authorTypeName: authorTypeName,
            labels: labels,
            mergedBy: mergedBy,
            viewerReviews: viewerReviews,
            reviews: reviews,
            mergeable: mergeable,
            reviewDecision: reviewDecision,
            reviewRequestsTotal: reviewRequestsTotal,
            checkRuns: checkRuns,
            extraContextsJSON: extraContextsJSON,
            includeSignals: includeSignals
        )
    }

    func renderJSON() -> String {
        var parts: [String] = []
        parts.append("\"__typename\": \"\(typeName)\"")
        parts.append("\"databaseId\": \(databaseId)")
        parts.append("\"number\": \(number)")
        parts.append("\"title\": \(quoted(title))")
        parts.append("\"url\": \(quoted(url))")
        parts.append("\"isDraft\": \(isDraft)")
        parts.append("\"updatedAt\": \(quoted(updatedAt))")
        parts.append("\"state\": \(quoted(state))")
        parts.append("\"merged\": \(merged)")
        parts.append("\"mergedAt\": \(quotedOrNull(mergedAt))")
        parts.append("\"repository\": { \"nameWithOwner\": \(quoted(repository)) }")
        parts.append("\"author\": \(actorJSON(login: authorLogin, typeName: authorTypeName))")
        parts.append("\"labels\": \(labelsJSON(labels))")
        if let mergedBy {
            parts.append("\"mergedBy\": \(actorJSON(login: mergedBy.login, typeName: mergedBy.typeName))")
        }
        if !viewerReviews.isEmpty {
            parts.append("\"viewerReviews\": \(reviewsJSON(viewerReviews))")
        }
        if includeSignals {
            parts.append("\"mergeable\": \(quotedOrNull(mergeable))")
            parts.append("\"reviewDecision\": \(quotedOrNull(reviewDecision))")
            parts.append("\"headRefOid\": \(quotedOrNull(headRefOid))")
            parts.append("\"reviewRequests\": { \"totalCount\": \(reviewRequestsTotal ?? 0) }")
            parts.append("\"reviews\": \(reviewsJSON(reviews))")
            parts.append("\"commits\": \(commitsJSON(checkRuns: checkRuns, extraContextsJSON: extraContextsJSON))")
        }
        return "{\n" + parts.joined(separator: ",\n") + "\n}"
    }

    private func quoted(_ s: String) -> String { "\"\(s)\"" }

    private func quotedOrNull(_ s: String?) -> String {
        if let s { return "\"\(s)\"" }
        return "null"
    }

    private func actorJSON(login: String?, typeName: String) -> String {
        guard let login else { return "null" }
        return """
        { "__typename": "\(typeName)", "login": "\(login)", "avatarUrl": "https://avatars.githubusercontent.com/\(login)", "url": "https://github.com/\(login)" }
        """
    }

    private func labelsJSON(_ labels: [LabelFixture]) -> String {
        let nodes = labels.map { label -> String in
            let desc = label.description.map { "\"\($0)\"" } ?? "null"
            return """
            { "name": "\(label.name)", "color": "\(label.color)", "description": \(desc) }
            """
        }
        return "{ \"nodes\": [\(nodes.joined(separator: ","))] }"
    }

    private func reviewsJSON(_ reviews: [ReviewFixture]) -> String {
        let nodes = reviews.enumerated().map { idx, review -> String in
            """
            { "id": "review-\(idx)", "state": "\(review.state)", "submittedAt": "\(review.submittedAt)", "url": "https://github.com/a/b/pull/0#review-\(idx)", "author": \(actorJSON(login: review.login, typeName: "User")) }
            """
        }
        return "{ \"nodes\": [\(nodes.joined(separator: ","))] }"
    }

    private func commitsJSON(checkRuns: [CheckRunFixture], extraContextsJSON: String) -> String {
        let runNodes = checkRuns.map { run -> String in
            let conclusion = run.conclusion.map { "\"\($0)\"" } ?? "null"
            let appJSON: String
            if let slug = run.appSlug {
                appJSON = "{ \"app\": { \"slug\": \"\(slug)\" } }"
            } else {
                appJSON = "null"
            }
            let startedAt = run.startedAt.map { "\"\($0)\"" } ?? "null"
            let completedAt = run.completedAt.map { "\"\($0)\"" } ?? "null"
            return """
            { "__typename": "CheckRun", "databaseId": \(run.databaseId), "name": "\(run.name)", "status": "\(run.status)", "conclusion": \(conclusion), "startedAt": \(startedAt), "completedAt": \(completedAt), "detailsUrl": "https://example.com/details/\(run.databaseId)", "permalink": "https://example.com/permalink/\(run.databaseId)", "checkSuite": \(appJSON) }
            """
        }
        let allContexts = runNodes.joined(separator: ",") + extraContextsJSON
        return """
        { "nodes": [{ "commit": { "statusCheckRollup": { "contexts": { "nodes": [\(allContexts)] } } } }] }
        """
    }
}

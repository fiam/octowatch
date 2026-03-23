import XCTest
@testable import Octowatch

final class PostMergeWatchPolicyTests: XCTestCase {
    func testDelaysSuccessWhileAnotherObservedPushRunIsPending() {
        let now = Date(timeIntervalSince1970: 1_000)
        let update = PostMergeWatchPolicy.apply(
            watch: makeWatch(mergedAt: now.addingTimeInterval(-60)),
            observation: PostMergeWatchObservation(
                resolution: .merged,
                mergedAt: now.addingTimeInterval(-60),
                mergeCommitSHA: "abc123",
                workflowRuns: [
                    makeRun(
                        id: 1,
                        title: "Dependency Submission",
                        status: "completed",
                        conclusion: "success",
                        createdAt: now.addingTimeInterval(-20)
                    ),
                    makeRun(
                        id: 2,
                        title: "Build",
                        status: "in_progress",
                        conclusion: nil,
                        createdAt: now.addingTimeInterval(-10)
                    )
                ]
            ),
            now: now
        )

        XCTAssertTrue(update.notifications.isEmpty)
        XCTAssertEqual(update.updatedWatch?.notifiedWorkflowRunIDs, [])
    }

    func testSendsDelayedSuccessOnceObservedPushRunsSettle() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let firstUpdate = PostMergeWatchPolicy.apply(
            watch: makeWatch(mergedAt: now.addingTimeInterval(-60)),
            observation: PostMergeWatchObservation(
                resolution: .merged,
                mergedAt: now.addingTimeInterval(-60),
                mergeCommitSHA: "abc123",
                workflowRuns: [
                    makeRun(
                        id: 1,
                        title: "Dependency Submission",
                        status: "completed",
                        conclusion: "success",
                        createdAt: now.addingTimeInterval(-20)
                    ),
                    makeRun(
                        id: 2,
                        title: "Build",
                        status: "in_progress",
                        conclusion: nil,
                        createdAt: now.addingTimeInterval(-10)
                    )
                ]
            ),
            now: now
        )

        let settledWatch = try XCTUnwrap(firstUpdate.updatedWatch)
        let settledUpdate = PostMergeWatchPolicy.apply(
            watch: settledWatch,
            observation: PostMergeWatchObservation(
                resolution: .merged,
                mergedAt: now.addingTimeInterval(-60),
                mergeCommitSHA: "abc123",
                workflowRuns: [
                    makeRun(
                        id: 1,
                        title: "Dependency Submission",
                        status: "completed",
                        conclusion: "success",
                        createdAt: now.addingTimeInterval(-20)
                    ),
                    makeRun(
                        id: 2,
                        title: "Build",
                        status: "completed",
                        conclusion: "success",
                        createdAt: now.addingTimeInterval(-5)
                    )
                ]
            ),
            now: now
        )

        XCTAssertEqual(
            settledUpdate.notifications.map(\.id).sorted(),
            [
                "post-merge:workflow:ExampleOrg/sample-services:1",
                "post-merge:workflow:ExampleOrg/sample-services:2"
            ]
        )
        XCTAssertEqual(
            settledUpdate.updatedWatch?.notifiedWorkflowRunIDs,
            [1, 2]
        )
    }

    func testStillSendsFailureWhileAnotherObservedPushRunIsPending() {
        let now = Date(timeIntervalSince1970: 1_000)
        let update = PostMergeWatchPolicy.apply(
            watch: makeWatch(mergedAt: now.addingTimeInterval(-60)),
            observation: PostMergeWatchObservation(
                resolution: .merged,
                mergedAt: now.addingTimeInterval(-60),
                mergeCommitSHA: "abc123",
                workflowRuns: [
                    makeRun(
                        id: 1,
                        title: "Build",
                        status: "completed",
                        conclusion: "failure",
                        createdAt: now.addingTimeInterval(-20)
                    ),
                    makeRun(
                        id: 2,
                        title: "Dependency Submission",
                        status: "in_progress",
                        conclusion: nil,
                        createdAt: now.addingTimeInterval(-10)
                    )
                ]
            ),
            now: now
        )

        XCTAssertEqual(update.notifications.map(\.title), ["Post-merge workflow failed"])
        XCTAssertEqual(update.updatedWatch?.notifiedWorkflowRunIDs, [1])
    }

    func testStillSendsApprovalRequiredWhileAnotherObservedPushRunIsPending() {
        let now = Date(timeIntervalSince1970: 1_000)
        let update = PostMergeWatchPolicy.apply(
            watch: makeWatch(mergedAt: now.addingTimeInterval(-60)),
            observation: PostMergeWatchObservation(
                resolution: .merged,
                mergedAt: now.addingTimeInterval(-60),
                mergeCommitSHA: "abc123",
                workflowRuns: [
                    makeRun(
                        id: 1,
                        title: "Deploy",
                        status: "action_required",
                        conclusion: nil,
                        createdAt: now.addingTimeInterval(-20)
                    ),
                    makeRun(
                        id: 2,
                        title: "Build",
                        status: "in_progress",
                        conclusion: nil,
                        createdAt: now.addingTimeInterval(-10)
                    )
                ]
            ),
            now: now
        )

        XCTAssertEqual(update.notifications.map(\.title), ["Workflow waiting for approval"])
        XCTAssertEqual(
            update.updatedWatch?.notifiedApprovalRequiredWorkflowRunIDs,
            [1]
        )
    }

    private func makeWatch(mergedAt: Date) -> PostMergeWatch {
        let reference = PullRequestReference(
            owner: "ExampleOrg",
            name: "sample-services",
            number: 1104
        )

        return PostMergeWatch(
            reference: reference,
            title: "[cloud-uc-services] sync uc-lease-protocol proto",
            repository: reference.repository,
            url: reference.pullRequestURL,
            createdAt: mergedAt.addingTimeInterval(-120),
            queuedAt: nil,
            mergedAt: mergedAt,
            mergeCommitSHA: "abc123",
            lastObservedWorkflowRunAt: nil,
            notifiedWorkflowRunIDs: [],
            notifiedApprovalRequiredWorkflowRunIDs: [],
            suppressedWorkflowItemIDs: []
        )
    }

    private func makeRun(
        id: Int,
        title: String,
        status: String,
        conclusion: String?,
        createdAt: Date
    ) -> PostMergeObservedWorkflowRun {
        PostMergeObservedWorkflowRun(
            id: id,
            workflowID: id,
            title: title,
            repository: "ExampleOrg/sample-services",
            url: URL(string: "https://github.com/ExampleOrg/sample-services/actions/runs/\(id)")!,
            event: "push",
            status: status,
            conclusion: conclusion,
            requiresApproval: false,
            createdAt: createdAt,
            actor: nil
        )
    }
}

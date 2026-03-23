import XCTest
@testable import Octowatch

final class WorkflowWatchCandidateSelectionTests: XCTestCase {
    func testSelectPrefersMostRecentlyUpdatedCandidateWithinPriority() {
        let now = Date()
        let selected = WorkflowWatchCandidateSelectionPolicy.select(
            [
                WorkflowWatchCandidate(
                    repository: "acme/cloud-infra-terraform",
                    number: 10,
                    relationship: .assigned,
                    updatedAt: now.addingTimeInterval(-60)
                ),
                WorkflowWatchCandidate(
                    repository: "ExampleOrg/cloud-uc-manifests",
                    number: 999,
                    relationship: .reviewed,
                    updatedAt: now.addingTimeInterval(-3_600)
                ),
                WorkflowWatchCandidate(
                    repository: "ExampleOrg/cloud-uc-manifests",
                    number: 646,
                    relationship: .reviewed,
                    updatedAt: now.addingTimeInterval(-300)
                )
            ],
            limit: 2
        )

        XCTAssertEqual(
            selected.map { "\($0.repository)#\($0.number)" },
            [
                "acme/cloud-infra-terraform#10",
                "ExampleOrg/cloud-uc-manifests#646"
            ]
        )
    }

    func testSelectKeepsHigherPriorityRelationshipForSamePullRequest() {
        let now = Date()
        let selected = WorkflowWatchCandidateSelectionPolicy.select(
            [
                WorkflowWatchCandidate(
                    repository: "ExampleOrg/cloud-uc-manifests",
                    number: 646,
                    relationship: .authored,
                    updatedAt: now
                ),
                WorkflowWatchCandidate(
                    repository: "ExampleOrg/cloud-uc-manifests",
                    number: 646,
                    relationship: .reviewed,
                    updatedAt: now.addingTimeInterval(-600)
                )
            ],
            limit: 8
        )

        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.relationship, .reviewed)
    }
}

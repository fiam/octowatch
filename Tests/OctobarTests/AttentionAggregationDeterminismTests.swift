import XCTest
@testable import Octowatch

/// Regression coverage for the "constantly re-notifying" bug on PRs that have
/// multiple workflow-approval items sharing one subjectKey.
///
/// When `AttentionSubjectViewPolicy.collapsingUpdates` aggregates many items
/// with the same subjectKey, equal type, and equal timestamp, the resulting
/// subjectItem.updateKey must be deterministic regardless of input order.
/// Upstream `mergedByRunID.values` iteration is non-deterministic, so if the
/// primary-item selection is order-sensitive, subjectItem.updateKey flips on
/// every poll and `notifyIfNeeded` fires a fresh notification each cycle.
final class AttentionAggregationDeterminismTests: XCTestCase {
    private let subjectKey = "https://github.com/moby/buildkit/pull/6444"
    private let prURL = URL(string: "https://github.com/moby/buildkit/pull/6444")!
    private let sharedTimestamp = Date(timeIntervalSince1970: 1_715_868_000)

    func testWorkflowApprovalSubjectItemIsStableAcrossInputPermutations() {
        let items = workflowApprovalRequiredItems(count: 6)

        let referenceUpdateKey = collapsedSubjectItem(items)?.updateKey
        XCTAssertNotNil(referenceUpdateKey)

        for permutation in permutations(of: items) {
            let aggregated = collapsedSubjectItem(permutation)
            XCTAssertEqual(
                aggregated?.updateKey,
                referenceUpdateKey,
                "Aggregated subject updateKey must not depend on input order"
            )
        }
    }

    func testEqualTimestampWorkflowRunsTieBreakOnUpdateKeyLexicographically() {
        // For tied timestamps the deterministic tiebreaker is the lexicographically
        // largest updateKey, since `max(by:)` returns whichever element is not less
        // than all others.
        let items = workflowApprovalRequiredItems(count: 6)
        let expected = items.max(by: { $0.updateKey < $1.updateKey })?.updateKey

        let aggregated = collapsedSubjectItem(items)
        XCTAssertEqual(aggregated?.updateKey, expected)
    }

    func testEarlierTimestampLosesEvenWhenUpdateKeyIsLexicographicallyLarger() {
        // Timestamp must still dominate updateKey ordering — the tiebreaker only
        // kicks in when timestamps and type priorities are equal.
        let later = workflowItem(
            updateKey: "run:111:workflowApprovalRequired:1715868000",
            timestamp: sharedTimestamp
        )
        let earlier = workflowItem(
            updateKey: "run:zzzzz:workflowApprovalRequired:1715867999",
            timestamp: sharedTimestamp.addingTimeInterval(-60)
        )

        let aggregated = collapsedSubjectItem([later, earlier])
        XCTAssertEqual(aggregated?.updateKey, later.updateKey)
    }

    func testAllPersistedUpdatesArePresentRegardlessOfPrimarySelection() {
        // Aggregation must not lose individual update rows — the "All updates"
        // history depends on every workflow run showing up exactly once.
        let items = workflowApprovalRequiredItems(count: 6)
        let aggregated = collapsedSubjectItem(items)

        let updates = aggregated?.detail.updates ?? []
        XCTAssertEqual(updates.count, items.count)
        XCTAssertEqual(
            Set(updates.map(\.id)),
            Set(items.map(\.updateKey))
        )
    }

    func testRelationshipItemSelectionIsAlsoOrderInvariant() {
        // Two review-requested items with identical timestamps must produce the
        // same subjectItem regardless of input order (the focusActor / type
        // shown in the inbox).
        let alpha = relationshipItem(
            id: "alpha",
            updateKey: "review-request:alpha",
            timestamp: sharedTimestamp
        )
        let beta = relationshipItem(
            id: "beta",
            updateKey: "review-request:beta",
            timestamp: sharedTimestamp
        )

        let lhs = collapsedSubjectItem([alpha, beta])
        let rhs = collapsedSubjectItem([beta, alpha])
        XCTAssertEqual(lhs?.updateKey, rhs?.updateKey)
    }

    // MARK: - Helpers

    private func collapsedSubjectItem(_ items: [AttentionItem]) -> AttentionItem? {
        AttentionSubjectViewPolicy.collapsingUpdates(in: items).first {
            $0.subjectKey == subjectKey
        }
    }

    private func workflowApprovalRequiredItems(count: Int) -> [AttentionItem] {
        (1...count).map { index in
            workflowItem(
                updateKey: "run:\(index * 7):workflowApprovalRequired:1715868000",
                timestamp: sharedTimestamp
            )
        }
    }

    private func workflowItem(updateKey: String, timestamp: Date) -> AttentionItem {
        AttentionItem(
            id: updateKey,
            subjectKey: subjectKey,
            updateKey: updateKey,
            stream: .pullRequests,
            type: .workflowApprovalRequired,
            title: "Approve workflows for #6444",
            subtitle: "moby/buildkit · Workflow waiting for approval",
            repository: "moby/buildkit",
            timestamp: timestamp,
            url: prURL
        )
    }

    private func relationshipItem(id: String, updateKey: String, timestamp: Date) -> AttentionItem {
        AttentionItem(
            id: id,
            subjectKey: subjectKey,
            updateKey: updateKey,
            stream: .pullRequests,
            type: .reviewRequested,
            title: "Reviews requested on #6444",
            subtitle: "moby/buildkit",
            repository: "moby/buildkit",
            timestamp: timestamp,
            url: prURL
        )
    }

    /// All N! permutations. Small N only (we use 6 → 720 permutations).
    private func permutations<T>(of items: [T]) -> [[T]] {
        guard items.count > 1 else { return [items] }
        var result: [[T]] = []
        for index in items.indices {
            var rest = items
            let pivot = rest.remove(at: index)
            for tail in permutations(of: rest) {
                result.append([pivot] + tail)
            }
        }
        return result
    }
}

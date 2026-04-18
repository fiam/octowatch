import XCTest
@testable import Octowatch

final class AttentionLocalReadStateTests: XCTestCase {
    func testReadOverrideKeepsOlderUnreadSnapshotRead() {
        let now = Date()

        XCTAssertFalse(
            AttentionLocalReadState.read(at: now).resolving(
                snapshotIsUnread: true,
                itemTimestamp: now.addingTimeInterval(-60)
            )
        )
    }

    func testReadOverrideAllowsNewUnreadSnapshotActivity() {
        let now = Date()

        XCTAssertTrue(
            AttentionLocalReadState.read(at: now).resolving(
                snapshotIsUnread: true,
                itemTimestamp: now.addingTimeInterval(60)
            )
        )
    }

    func testUnreadOverrideMakesReadSnapshotVisibleAsUnread() {
        XCTAssertTrue(
            AttentionLocalReadState.unread.resolving(
                snapshotIsUnread: false,
                itemTimestamp: Date()
            )
        )
    }
}

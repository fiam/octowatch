import XCTest
import UserNotifications
@testable import Octowatch

@MainActor
final class UserNotifierTests: XCTestCase {
    func testSubjectNotificationsReplaceExistingNotificationForSameSubject() async {
        let center = FakeUserNotificationCenter()
        let notifier = UserNotifier(center: center)
        let url = URL(string: "https://github.com/example/repo/pull/42")!
        let item = AttentionItem(
            id: "subject:https://github.com/example/repo/pull/42",
            subjectKey: url.absoluteString,
            updateKey: "notif:42:comment:200",
            type: .comment,
            title: "Example pull request",
            subtitle: "example/repo · New comment",
            timestamp: Date(timeIntervalSince1970: 200),
            url: url
        )

        let addExpectation = expectation(description: "notification added")
        center.onAdd = { request in
            XCTAssertEqual(request.identifier, url.absoluteString)
            XCTAssertEqual(request.content.threadIdentifier, url.absoluteString)
            XCTAssertEqual(request.content.userInfo["subjectKey"] as? String, url.absoluteString)
            XCTAssertEqual(
                request.content.userInfo["updateKey"] as? String,
                "notif:42:comment:200"
            )
            addExpectation.fulfill()
        }

        notifier.notify(item: item)

        await fulfillment(of: [addExpectation], timeout: 1)
        XCTAssertEqual(center.removedPendingIdentifiers, [url.absoluteString])
        XCTAssertEqual(center.removedDeliveredIdentifiers, [url.absoluteString])
    }

    func testRemovingSubjectNotificationsClearsPendingAndDeliveredNotifications() {
        let center = FakeUserNotificationCenter()
        let notifier = UserNotifier(center: center)

        notifier.removeSubjectNotifications(
            subjectKeys: [
                "https://github.com/example/repo/pull/42",
                "https://github.com/example/repo/pull/42",
                "https://github.com/example/repo/issues/7"
            ]
        )

        XCTAssertEqual(
            Set(center.removedPendingIdentifiers),
            [
                "https://github.com/example/repo/pull/42",
                "https://github.com/example/repo/issues/7"
            ]
        )
        XCTAssertEqual(
            Set(center.removedDeliveredIdentifiers),
            [
                "https://github.com/example/repo/pull/42",
                "https://github.com/example/repo/issues/7"
            ]
        )
    }
}

@MainActor
private final class FakeUserNotificationCenter: UserNotificationCenterProtocol {
    var removedPendingIdentifiers: [String] = []
    var removedDeliveredIdentifiers: [String] = []
    var onAdd: ((UNNotificationRequest) -> Void)?

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {
        onAdd?(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifiers.append(contentsOf: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.append(contentsOf: identifiers)
    }
}

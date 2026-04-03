import Foundation
import UserNotifications

@MainActor
protocol UserNotificationCenterProtocol: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCenterProtocol {}

@MainActor
final class UserNotifier {
    private let center: any UserNotificationCenterProtocol

    init(center: any UserNotificationCenterProtocol = UNUserNotificationCenter.current()) {
        self.center = center
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Keep running without local notifications.
        }
    }

    func notify(item: AttentionItem) {
        replaceSubjectNotification(
            subjectKey: item.subjectKey,
            updateKey: item.updateKey,
            title: item.nativeNotificationTitle,
            subtitle: item.title,
            body: item.subtitle,
            url: item.url
        )
    }

    func notify(transition: AttentionTransitionNotification) {
        notify(
            identifier: transition.id,
            subjectKey: transition.subjectKey,
            title: transition.title,
            subtitle: transition.subtitle,
            body: transition.body,
            url: transition.url
        )
    }

    func removeSubjectNotifications(subjectKeys: [String]) {
        let identifiers = Array(Set(subjectKeys))
        guard !identifiers.isEmpty else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func notify(
        identifier: String,
        subjectKey: String?,
        title: String,
        subtitle: String,
        body: String,
        url: URL
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        var userInfo: [String: String] = ["url": url.absoluteString]
        if let subjectKey {
            userInfo["subjectKey"] = subjectKey
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        Task {
            try? await center.add(request)
        }
    }

    private func replaceSubjectNotification(
        subjectKey: String,
        updateKey: String,
        title: String,
        subtitle: String,
        body: String,
        url: URL
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [subjectKey])
        center.removeDeliveredNotifications(withIdentifiers: [subjectKey])

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = subjectKey
        content.userInfo = [
            "url": url.absoluteString,
            "subjectKey": subjectKey,
            "updateKey": updateKey
        ]

        let request = UNNotificationRequest(
            identifier: subjectKey,
            content: content,
            trigger: nil
        )

        Task {
            try? await center.add(request)
        }
    }
}

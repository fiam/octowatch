import Foundation
import UserNotifications

@MainActor
final class UserNotifier {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Keep running without local notifications.
        }
    }

    func notify(item: AttentionItem) {
        notify(
            identifier: item.id,
            title: item.nativeNotificationTitle,
            subtitle: item.title,
            body: item.subtitle,
            url: item.url
        )
    }

    func notify(transition: AttentionTransitionNotification) {
        notify(
            identifier: transition.id,
            title: transition.title,
            subtitle: transition.subtitle,
            body: transition.body,
            url: transition.url
        )
    }

    private func notify(
        identifier: String,
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
        content.userInfo = ["url": url.absoluteString]

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        center.add(request)
    }
}

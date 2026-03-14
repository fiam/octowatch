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
        let content = UNMutableNotificationContent()
        content.title = item.nativeNotificationTitle
        content.subtitle = item.title
        content.body = item.subtitle
        content.sound = .default
        content.userInfo = ["url": item.url.absoluteString]

        let request = UNNotificationRequest(
            identifier: item.id,
            content: content,
            trigger: nil
        )

        center.add(request)
    }
}

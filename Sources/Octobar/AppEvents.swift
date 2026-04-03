import Foundation

enum AppSceneID {
    static let mainWindow = "main-window"
    static let ignoredItemsWindow = "ignored-items-window"
    static let snoozedItemsWindow = "snoozed-items-window"
}

struct AttentionSubjectNavigationRequest: Hashable {
    private static let subjectKeyUserInfoKey = "attentionSubjectKey"

    let subjectKey: String

    var userInfo: [AnyHashable: Any] {
        [Self.subjectKeyUserInfoKey: subjectKey]
    }

    init(subjectKey: String) {
        self.subjectKey = subjectKey
    }

    init?(notification: Notification) {
        guard
            let subjectKey = notification.userInfo?[Self.subjectKeyUserInfoKey] as? String,
            !subjectKey.isEmpty
        else {
            return nil
        }

        self.init(subjectKey: subjectKey)
    }
}

extension Notification.Name {
    static let openMainWindowRequested = Notification.Name("OctowatchOpenMainWindowRequested")
    static let performMainWindowOpen = Notification.Name("OctowatchPerformMainWindowOpen")
    static let focusAttentionSubjectRequested = Notification.Name("OctowatchFocusAttentionSubjectRequested")
    static let openSettingsRequested = Notification.Name("OctowatchOpenSettingsRequested")
    static let performSettingsOpen = Notification.Name("OctowatchPerformSettingsOpen")
}

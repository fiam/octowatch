import Foundation

enum AppSceneID {
    static let mainWindow = "main-window"
}

extension Notification.Name {
    static let openMainWindowRequested = Notification.Name("OctowatchOpenMainWindowRequested")
    static let performMainWindowOpen = Notification.Name("OctowatchPerformMainWindowOpen")
    static let openSettingsRequested = Notification.Name("OctowatchOpenSettingsRequested")
    static let performSettingsOpen = Notification.Name("OctowatchPerformSettingsOpen")
}

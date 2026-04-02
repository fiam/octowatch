import SwiftUI

@main
struct OctowatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("Octowatch", id: AppSceneID.mainWindow) {
            AttentionWindowView(model: model)
        }
        .defaultSize(width: 1080, height: 720)

        Window("Ignored Items", id: AppSceneID.ignoredItemsWindow) {
            IgnoredItemsView(model: model)
        }
        .defaultSize(width: 720, height: 520)

        Window("Snoozed Items", id: AppSceneID.snoozedItemsWindow) {
            SnoozedItemsView(model: model)
        }
        .defaultSize(width: 720, height: 520)

        Settings {
            SettingsView(model: model)
        }
        .defaultSize(width: 760, height: 520)
        .windowResizability(.contentSize)
    }
}

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

        Settings {
            SettingsView(model: model)
        }
        .defaultSize(width: 760, height: 520)
        .windowResizability(.contentSize)
    }
}

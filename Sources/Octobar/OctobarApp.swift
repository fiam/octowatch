import SwiftUI

@main
struct OctowatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared
    private let appUpdateController = AppUpdateController.shared

    var body: some Scene {
        Window("Octowatch", id: AppSceneID.mainWindow) {
            AttentionWindowView(model: model)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appUpdateController.checkForUpdates()
                }
                .disabled(!appUpdateController.isAvailable)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("Ignored Items", id: AppSceneID.ignoredItemsWindow) {
            IgnoredItemsView(model: model)
        }
        .defaultSize(width: 720, height: 520)

        Window("Snoozed Items", id: AppSceneID.snoozedItemsWindow) {
            SnoozedItemsView(model: model)
        }
        .defaultSize(width: 720, height: 520)

        Window("Octowatch Settings", id: AppSceneID.settingsWindow) {
            SettingsView(model: model)
        }
        .defaultSize(width: 760, height: 500)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
    }
}

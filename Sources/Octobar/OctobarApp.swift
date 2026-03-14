import SwiftUI

@main
struct OctobarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Settings {
            SettingsView(model: model)
        }
    }
}

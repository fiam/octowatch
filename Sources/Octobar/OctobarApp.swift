import AppKit
import SwiftUI

@main
struct OctobarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            if model.actionableCount > 0 {
                Label("\(model.actionableCount)", systemImage: "bell.badge.fill")
            } else {
                Label("Octobar", systemImage: "bell")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

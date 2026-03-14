import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct StatusPresentation: Equatable {
        let symbolName: String
        let title: String
        let toolTip: String
    }

    private let model = AppModel.shared
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var modelChangeCancellable: AnyCancellable?
    private var lastStatusPresentation: StatusPresentation?
    private weak var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
        observeAppEvents()
        observeModelChanges()
        observeWindowLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(model: model)
        )
        // Make sure SwiftUI observers are active before first context-menu action.
        _ = popover.contentViewController?.view
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.imagePosition = .imageLeading
        updateStatusItemButton()
    }

    private func observeModelChanges() {
        modelChangeCancellable = model.$attentionItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemButton()
            }
    }

    private func observeAppEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettingsRequested(_:)),
            name: .openSettingsRequested,
            object: nil
        )
    }

    private func observeWindowLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    private func updateStatusItemButton() {
        guard let button = statusItem?.button else {
            return
        }

        let hasUnread = model.unreadCount > 0
        let symbolName = hasUnread ? "bell.badge.fill" : "bell"

        let count: Int?
        if hasUnread {
            count = model.unreadCount
        } else if model.actionableCount > 0 {
            count = model.actionableCount
        } else {
            count = nil
        }

        let title = count.map { " \($0)" } ?? ""
        let toolTip = count.map { "\($0) GitHub items need attention." } ?? "Octobar"
        let presentation = StatusPresentation(
            symbolName: symbolName,
            title: title,
            toolTip: toolTip
        )

        guard presentation != lastStatusPresentation else {
            return
        }

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Octobar"
        )?.withSymbolConfiguration(symbolConfig)
        button.title = title
        button.toolTip = toolTip

        lastStatusPresentation = presentation
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(relativeTo: sender)
            return
        }

        if event.type == .rightMouseDown || event.type == .rightMouseUp {
            showContextMenu(with: event, relativeTo: sender)
            return
        }

        togglePopover(relativeTo: sender)
    }

    private func showContextMenu(with event: NSEvent, relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromContextMenu),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit Octobar",
            action: #selector(quitFromContextMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc
    private func openSettingsFromContextMenu() {
        openSettingsWindow()
    }

    @objc
    private func quitFromContextMenu() {
        NSApplication.shared.terminate(nil)
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc
    private func handleOpenSettingsRequested(_ notification: Notification) {
        openSettingsWindow()
    }

    @objc
    private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            isSettingsWindow(window)
        else {
            return
        }

        settingsWindow = window
        NSApp.setActivationPolicy(.regular)
    }

    @objc
    private func handleWindowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            window === settingsWindow
        else {
            return
        }

        settingsWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel {
            return false
        }

        return window.styleMask.contains(.titled)
    }

    private func openSettingsWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            NotificationCenter.default.post(name: .performSettingsOpen, object: nil)
            self?.focusSettingsWindowWhenAvailable()
        }
    }

    private func focusSettingsWindowWhenAvailable(retries: Int = 12) {
        if let window = findSettingsWindow() {
            settingsWindow = window
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard retries > 0 else {
            if settingsWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusSettingsWindowWhenAvailable(retries: retries - 1)
        }
    }

    private func findSettingsWindow() -> NSWindow? {
        if let settingsWindow, settingsWindow.isVisible {
            return settingsWindow
        }

        if let titledByName = NSApp.windows.first(where: {
            isSettingsWindow($0) && $0.title.localizedCaseInsensitiveContains("settings")
        }) {
            return titledByName
        }

        return NSApp.windows.first(where: isSettingsWindow)
    }
}

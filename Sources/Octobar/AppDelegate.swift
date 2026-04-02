import AppKit
import Combine
import SwiftUI
import UserNotifications

struct MenuBarStatusPresentation: Equatable {
    let imageName: String
    let fallbackSymbolName: String
    let toolTip: String

    init(inboxSections: [InboxSectionPolicy.SectionResult]) {
        let items = inboxSections.flatMap(\.items)
        let unreadCount = items.filter(\.isUnread).count

        if unreadCount > 0 {
            imageName = "MenuBarIconAlert"
            fallbackSymbolName = "bell.badge.fill"
            toolTip = Self.tooltip(itemCount: unreadCount, prefix: "unread")
        } else if items.isEmpty {
            imageName = "MenuBarIcon"
            fallbackSymbolName = "bell"
            toolTip = "Octowatch"
        } else {
            imageName = "MenuBarIcon"
            fallbackSymbolName = "bell"
            toolTip = Self.tooltip(itemCount: items.count)
        }
    }

    private static func tooltip(itemCount: Int, prefix: String? = nil) -> String {
        let itemLabel = itemCount == 1 ? "item" : "items"
        let prefixText = prefix.map { "\($0) " } ?? ""
        return "\(itemCount) \(prefixText)\(itemLabel) in your inbox."
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate {
    private enum MenuBarPopoverMetrics {
        static let width: CGFloat = 360
        static let minHeight: CGFloat = 120
        static let maxHeight: CGFloat = 520
    }

    private let model = AppModel.shared
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var popoverHostingController: NSHostingController<MenuBarContentView>?
    private var modelChangeCancellable: AnyCancellable?
    private var popoverLayoutChangeCancellable: AnyCancellable?
    private var lastStatusPresentation: MenuBarStatusPresentation?
    private weak var mainWindow: NSWindow?
    private weak var settingsWindow: NSWindow?
    private var localPopoverEventMonitor: Any?
    private var globalPopoverEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        observeAppEvents()
        observeModelChanges()
        observeWindowLifecycle()
        modelNotifierSetup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        let hostingController = NSHostingController(
            rootView: MenuBarContentView(model: model)
        )
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = [.preferredContentSize]
        }
        popoverHostingController = hostingController
        popover.contentViewController = hostingController
        updatePopoverContentSize()
        // Make sure SwiftUI observers are active before first context-menu action.
        _ = popover.contentViewController?.view
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        updateStatusItemButton()
    }

    private func observeModelChanges() {
        modelChangeCancellable = model.$inboxSections
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemButton()
            }

        popoverLayoutChangeCancellable = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updatePopoverContentSize()
                }
            }
    }

    private func observeAppEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMainWindowRequested(_:)),
            name: .openMainWindowRequested,
            object: nil
        )
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

    private func modelNotifierSetup() {
        UNUserNotificationCenter.current().delegate = self
    }

    private func updateStatusItemButton() {
        guard let button = statusItem?.button else {
            return
        }

        let presentation = MenuBarStatusPresentation(inboxSections: model.inboxSections)

        guard presentation != lastStatusPresentation else {
            return
        }

        button.image = statusItemImage(
            named: presentation.imageName,
            fallbackSymbolName: presentation.fallbackSymbolName
        )
        button.title = ""
        button.toolTip = presentation.toolTip

        lastStatusPresentation = presentation
    }

    private func statusItemImage(named assetName: String, fallbackSymbolName: String) -> NSImage? {
        if let assetImage = NSImage(named: assetName)?.copy() as? NSImage {
            assetImage.isTemplate = true
            assetImage.size = NSSize(width: 18, height: 18)
            return assetImage
        }

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        return NSImage(
            systemSymbolName: fallbackSymbolName,
            accessibilityDescription: "Octowatch"
        )?.withSymbolConfiguration(symbolConfig)
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

        let openItem = NSMenuItem(
            title: "Open Octowatch",
            action: #selector(openMainWindowFromContextMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromContextMenu),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit Octowatch",
            action: #selector(quitFromContextMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc
    private func openMainWindowFromContextMenu() {
        openMainWindow()
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

        updatePopoverContentSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installPopoverDismissMonitors()
    }

    private func updatePopoverContentSize() {
        guard let hostingController = popoverHostingController else {
            return
        }

        hostingController.view.layoutSubtreeIfNeeded()

        let fittingWidth = MenuBarPopoverMetrics.width
        var fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: fittingWidth, height: .greatestFiniteMagnitude)
        )

        if !fittingSize.width.isFinite || fittingSize.width <= 0 {
            fittingSize.width = fittingWidth
        }

        if !fittingSize.height.isFinite || fittingSize.height <= 0 {
            fittingSize.height = MenuBarPopoverMetrics.minHeight
        }

        let contentSize = NSSize(
            width: fittingWidth,
            height: min(
                max(ceil(fittingSize.height), MenuBarPopoverMetrics.minHeight),
                MenuBarPopoverMetrics.maxHeight
            )
        )

        guard popover.contentSize != contentSize else {
            return
        }

        popover.contentSize = contentSize
    }

    @objc
    private func handleOpenMainWindowRequested(_ notification: Notification) {
        openMainWindow()
    }

    @objc
    private func handleOpenSettingsRequested(_ notification: Notification) {
        openSettingsWindow()
    }

    @objc
    private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            isSettingsWindow(window) || isMainWindow(window)
        else {
            return
        }

        if isSettingsWindow(window) {
            settingsWindow = window
        } else if isMainWindow(window) {
            mainWindow = window
        }
    }

    @objc
    private func handleWindowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            window === settingsWindow || window === mainWindow
        else {
            return
        }

        if window === settingsWindow {
            settingsWindow = nil
        } else if window === mainWindow {
            mainWindow = nil
        }
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.styleMask.contains(.titled) else {
            return false
        }

        return !isSettingsWindow(window)
    }

    private func openMainWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            NotificationCenter.default.post(name: .performMainWindowOpen, object: nil)
            self?.focusMainWindowWhenAvailable()
        }
    }

    private func focusMainWindowWhenAvailable(retries: Int = 12) {
        if let window = findMainWindow() {
            mainWindow = window
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard retries > 0 else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusMainWindowWhenAvailable(retries: retries - 1)
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel || !window.styleMask.contains(.titled) {
            return false
        }

        return window.title.localizedCaseInsensitiveContains("settings")
    }

    private func openSettingsWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            NotificationCenter.default.post(name: .performSettingsOpen, object: nil)
            self?.focusSettingsWindowWhenAvailable()
        }
    }

    private func focusSettingsWindowWhenAvailable(retries: Int = 12) {
        if let window = findSettingsWindow() {
            settingsWindow = window
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard retries > 0 else {
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

    private func findMainWindow() -> NSWindow? {
        if let mainWindow, mainWindow.isVisible {
            return mainWindow
        }

        if let titledByName = NSApp.windows.first(where: {
            isMainWindow($0) && $0.title.localizedCaseInsensitiveContains("octowatch")
        }) {
            return titledByName
        }

        return NSApp.windows.first(where: isMainWindow)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            openMainWindow()
            return false
        }

        return true
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.removePopoverDismissMonitors()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            let rawURL = response.notification.request.content.userInfo["url"] as? String,
            let url = URL(string: rawURL)
        else {
            return
        }

        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            NSWorkspace.shared.open(url)
        }
    }

    private func installPopoverDismissMonitors() {
        removePopoverDismissMonitors()

        localPopoverEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else {
                return event
            }

            if self.shouldClosePopover(for: event) {
                self.popover.performClose(nil)
            }

            return event
        }

        globalPopoverEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.popover.performClose(nil)
            }
        }
    }

    private func removePopoverDismissMonitors() {
        if let localPopoverEventMonitor {
            NSEvent.removeMonitor(localPopoverEventMonitor)
            self.localPopoverEventMonitor = nil
        }

        if let globalPopoverEventMonitor {
            NSEvent.removeMonitor(globalPopoverEventMonitor)
            self.globalPopoverEventMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover.isShown else {
            return false
        }

        if let statusWindow = statusItem?.button?.window, event.window === statusWindow {
            return false
        }

        if let popoverWindow = popover.contentViewController?.view.window, event.window === popoverWindow {
            return false
        }

        return true
    }
}

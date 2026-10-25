import AppKit
import Darwin
import SimFlutDockCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var coordinator: PanelCoordinator!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var logsWindow: NSWindow?
    private var activationToken: NSObjectProtocol?
    private var exiting = false
    private var sessionControl: SessionControl?
    private var controlServer: LocalControlServer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        let control = SessionControl(manager: model.manager, store: model.store, globalSDK: { [weak model] in model?.globalSDK })
        let server = LocalControlServer { data in await control.handle(data) }
        do {
            try server.start()
            sessionControl = control
            controlServer = server
        } catch {
            NSLog("Fluttios local session control could not start: %@", error.localizedDescription)
        }
        model.showSettings = { [weak self] in self?.showSettings() }
        model.showLogs = { [weak self] in self?.showLogs() }
        model.showPanel = { [weak self] in self?.coordinator.show() }
        coordinator = PanelCoordinator(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let appIcon = NSImage(contentsOf: iconURL)
        {
            NSApp.applicationIconImage = appIcon
            let menuIcon = appIcon.copy() as! NSImage
            menuIcon.size = NSSize(width: 20, height: 20)
            menuIcon.isTemplate = false
            menuIcon.accessibilityDescription = "SimFlutDock"
            statusItem.button?.image = menuIcon
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "SimFlutDock")
        }
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = L10n.text("SimFlutDock — show simulator or panel")
        model.languageDidChange = { [weak self] in self?.updateLocalizedTitles() }
        model.quitApp = { NSApp.terminate(nil) }
        activationToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.background.refresh()
                self?.model.tracker.refresh()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-panel-follow") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.coordinator.show() }
        } else {
            model.updater.checkAutomatically()
        }
    }
    private func updateLocalizedTitles() {
        statusItem.button?.toolTip = L10n.text("SimFlutDock — show simulator or panel")
        settingsWindow?.title = L10n.text("SimFlutDock — Projects and Settings")
        logsWindow?.title = L10n.text("SimFlutDock — Logs")
    }
    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent,
            event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        {
            showSettings()
            return
        }
        guard let button = statusItem.button else { return }
        coordinator.show(from: button)
    }
    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = window(
                title: L10n.text("SimFlutDock — Projects and Settings"), size: CGSize(width: 1040, height: 780),
                root: SettingsView(model: model))
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let settingsWindow { coordinator.avoidCoveringSettings(settingsWindow) }
    }
    @objc private func showLogs() {
        if logsWindow == nil {
            logsWindow = window(
                title: L10n.text("SimFlutDock — Logs"), size: CGSize(width: 860, height: 520),
                root: LogsView(model: model))
        }
        logsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func window<V: View>(title: String, size: CGSize, root: V) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        controlServer?.stop()
        model.updater.discardPreparedUpdateOnQuit()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again keeps it in the menu bar. Windows are explicit actions.
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if exiting { return .terminateLater }
        guard model.manager.hasActiveSessions else {
            return model.updater.handOffInstallation() ? .terminateNow : .terminateCancel
        }
        let alert = NSAlert()
        alert.messageText = L10n.text("Stop Flutter sessions and quit?")
        alert.informativeText = L10n.text(
            "Running projects will be stopped. Press Run again the next time you open SimFlutDock.")
        alert.addButton(withTitle: L10n.text("Stop All and Quit"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            model.updater.installationRequested = false
            return .terminateCancel
        }
        exiting = true
        Task {
            await model.manager.waitForStop()
            let shouldQuit = model.updater.handOffInstallation()
            if !shouldQuit {
                model.manager.cancelShutdown()
                exiting = false
            }
            NSApp.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }
    deinit { if let activationToken { NotificationCenter.default.removeObserver(activationToken) } }
}

let lockURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Fluttios/app.lock")
try? FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let lockFD = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.fluttios.app").first?.activate(options: [])
    exit(0)
}
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}

import AppKit
import Darwin

// Lifetime lock prevents duplicate helper instances, including a manual launch.
let lockURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fluttios/helper.lock")
try? FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let lockFD = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }

final class Helper: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []
    private var simulatorRunning = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  ["com.apple.iphonesimulator", "com.apple.dt.Devices"].contains(app.bundleIdentifier ?? "") else { return }
            self?.simulatorRunning = true
            self?.showParent()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.simulatorRunning = ["com.apple.iphonesimulator", "com.apple.dt.Devices"].contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
            // Parent independently receives the same event, hides its panel, and keeps
            // session state tied to Flutter events. The helper continues waiting.
        })
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.fluttios.helper.quit"), object: nil, queue: .main) { _ in NSApp.terminate(nil) })
        if ["com.apple.iphonesimulator", "com.apple.dt.Devices"].contains(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) { simulatorRunning = true; showParent() }
    }
    private func showParent() {
        // .../Fluttios.app/Contents/Library/LoginItems/FluttiosHelper.app
        var url = Bundle.main.bundleURL
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let config = NSWorkspace.OpenConfiguration(); config.activates = false; config.arguments = ["--background"]
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
    }
    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer); DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
let delegate = Helper()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()

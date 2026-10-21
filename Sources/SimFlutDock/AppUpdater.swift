import AppKit
import SimFlutDockCore
import SwiftUI

@MainActor final class AppUpdater: ObservableObject {
    enum State {
        case idle, checking, current
        case available(AppUpdate)
        case downloading(AppUpdate)
        case ready(PreparedAppUpdate)
        case failed(String)
    }
    @Published private(set) var state: State = .idle
    @Published var automaticallyChecks: Bool =
        UserDefaults.standard.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
    {
        didSet { UserDefaults.standard.set(automaticallyChecks, forKey: "automaticallyChecksForUpdates") }
    }
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private let service = AppUpdateService()
    private var task: Task<Void, Never>?
    private var window: NSWindow?
    private var manuallyRequested = false
    var installationRequested = false
    var busy: Bool {
        switch state {
        case .checking, .downloading: return true
        default: return false
        }
    }
    var readyToInstall: Bool {
        if case .ready = state { return true }
        return false
    }

    func checkAutomatically() {
        // Command-line verification runs have no bundle version and must not show update UI.
        guard automaticallyChecks, !currentVersion.isEmpty else { return }
        let last = UserDefaults.standard.object(forKey: "lastAutomaticUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 24 * 60 * 60 else { return }
        check(manual: false)
    }

    func check(manual: Bool = true) {
        if manual {
            manuallyRequested = true
            showWindow()
        }
        guard !busy else { return }
        if manual, case .ready = state { return }
        manuallyRequested = manual
        state = .checking
        UserDefaults.standard.set(Date(), forKey: "lastAutomaticUpdateCheck")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let update = try await service.check(currentVersion: currentVersion)
                try Task.checkCancellation()
                if let update {
                    state = .available(update)
                    if manuallyRequested {
                        try await downloadAndPrepare(update)
                    } else if automaticallyChecks {
                        showWindow()
                    }
                } else {
                    state = .current
                }
            } catch {
                if Task.isCancelled { state = .idle } else { state = .failed(error.localizedDescription) }
                // Background network failures remain silent; a manual check shows the error.
            }
            task = nil
        }
    }

    func download(_ update: AppUpdate) {
        guard !busy else { return }
        state = .downloading(update)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await downloadAndPrepare(update)
            } catch {
                if Task.isCancelled { state = .available(update) } else { state = .failed(error.localizedDescription) }
            }
            task = nil
        }
    }

    func cancel() { task?.cancel() }

    private func downloadAndPrepare(_ update: AppUpdate) async throws {
        state = .downloading(update)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SimFlutDock-downloads", isDirectory: true)
        let installer = try await service.download(update, downloadsDirectory: cache)
        defer { try? FileManager.default.removeItem(at: installer.deletingLastPathComponent()) }
        let prepared = try await service.prepareInstallation(
            installer: installer, update: update, destination: Bundle.main.bundleURL)
        guard !Task.isCancelled else {
            try? FileManager.default.removeItem(at: prepared.directory)
            throw CancellationError()
        }
        state = .ready(prepared)
        showWindow()
    }

    func install() {
        guard case .ready = state else { return }
        installationRequested = true
        NSApp.terminate(nil)
    }

    /// Called only after the normal quit confirmation and session shutdown succeed.
    func handOffInstallation() -> Bool {
        guard installationRequested, case .ready(let prepared) = state else { return true }
        do {
            try prepared.launchInstaller(parentPID: ProcessInfo.processInfo.processIdentifier)
            return true
        } catch {
            installationRequested = false
            try? FileManager.default.removeItem(at: prepared.directory)
            state = .failed(error.localizedDescription)
            showWindow()
            return false
        }
    }

    func discardPreparedUpdateOnQuit() {
        if !installationRequested, case .ready(let prepared) = state {
            try? FileManager.default.removeItem(at: prepared.directory)
        }
    }

    private func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 440, height: 360)
            window.contentView = NSHostingView(rootView: AppUpdateView(updater: self))
            window.center()
            self.window = window
        }
        window?.title = "SimFlutDock"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AppUpdateView: View {
    @ObservedObject var updater: AppUpdater
    @AppStorage(L10n.preferenceKey) private var language = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(L10n.text("App Updates"), systemImage: "arrow.down.circle")
                    .font(.title2.bold())
                switch updater.state {
                case .idle:
                    Text(L10n.text("Check for a newer version of SimFlutDock."))
                    checkButton
                case .checking:
                    ProgressView(L10n.text("Checking for updates…"))
                    Button(L10n.text("Cancel")) { updater.cancel() }
                case .current:
                    Text(L10n.text("SimFlutDock {0} is up to date.", updater.currentVersion))
                    checkButton
                case .available(let update):
                    Text(
                        L10n.text(
                            "SimFlutDock {0} is available. Installed: {1}.", update.version.description,
                            updater.currentVersion))
                    if !update.notes.isEmpty {
                        ScrollView {
                            Text(update.notes).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                    Text(
                        L10n.text(
                            "Download size: {0}",
                            ByteCountFormatter.string(fromByteCount: update.size, countStyle: .file))
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    Text(
                        L10n.text(
                            "The update will be downloaded and prepared automatically. You choose when to quit and install it."
                        )
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    Button(L10n.text("Download Update")) { updater.download(update) }
                        .keyboardShortcut(.defaultAction)
                case .downloading:
                    ProgressView(L10n.text("Downloading, verifying, and preparing the update…"))
                    Button(L10n.text("Cancel Download")) { updater.cancel() }
                case .ready:
                    Text(L10n.text("The update is ready to install."))
                    Text(
                        L10n.text(
                            "SimFlutDock will quit, replace the current version, and reopen automatically. Running Flutter sessions will be stopped with your confirmation."
                        )
                    )
                    .font(.callout)
                    Button(L10n.text("Quit and Install")) { updater.install() }
                        .keyboardShortcut(.defaultAction)
                case .failed(let message):
                    Label(L10n.text("Could not update SimFlutDock"), systemImage: "exclamationmark.triangle")
                    Text(L10n.display(message)).font(.callout).textSelection(.enabled)
                    checkButton
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(language)
    }

    private var checkButton: some View {
        Button(L10n.text("Check for Updates…")) { updater.check() }
    }
}

struct AppUpdateSettings: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggle(
                title: L10n.text("Automatically check for updates"),
                subtitle: L10n.text("Checks at launch, at most once a day. A manual check also downloads the update."),
                isOn: $updater.automaticallyChecks)
            Divider()
            SettingsField(L10n.text("Check for a newer version of SimFlutDock.")) {
                Button(L10n.text(updater.readyToInstall ? "Install Update…" : "Check for Updates…")) { updater.check() }
                    .disabled(updater.busy).controlSize(.small)
            }
        }
    }
}

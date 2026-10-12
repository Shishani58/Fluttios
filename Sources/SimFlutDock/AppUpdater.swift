import AppKit
import SwiftUI
import SimFlutDockCore

@MainActor final class AppUpdater: ObservableObject {
    enum State {
        case idle, checking, current, available(AppUpdate), downloading(AppUpdate), ready(URL), failed(String)
    }
    @Published private(set) var state: State = .idle
    @Published var automaticallyChecks: Bool = UserDefaults.standard.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automaticallyChecks, forKey: "automaticallyChecksForUpdates") }
    }
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private let service = AppUpdateService()
    private var task: Task<Void, Never>?
    private var window: NSWindow?
    private var manuallyRequested = false
    var busy: Bool {
        switch state { case .checking, .downloading: return true; default: return false }
    }

    func checkAutomatically() {
        // Command-line verification runs have no bundle version and must not show update UI.
        guard automaticallyChecks, !currentVersion.isEmpty else { return }
        let last = UserDefaults.standard.object(forKey: "lastAutomaticUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 24 * 60 * 60 else { return }
        check(manual: false)
    }

    func check(manual: Bool = true) {
        if manual { manuallyRequested = true; showWindow() }
        guard !busy else { return }
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
                    if manuallyRequested || automaticallyChecks { showWindow() }
                } else { state = .current }
            } catch {
                if Task.isCancelled { state = .idle }
                else { state = .failed(error.localizedDescription) }
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
                let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let installer = try await service.download(update, downloadsDirectory: downloads)
                state = .ready(installer)
                openInstaller(installer)
            } catch {
                if Task.isCancelled { state = .available(update) }
                else { state = .failed(error.localizedDescription) }
            }
            task = nil
        }
    }

    func cancel() { task?.cancel() }

    func openInstaller(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
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
                    Text(L10n.text("SimFlutDock {0} is available. Installed: {1}.", update.version.description, updater.currentVersion))
                    if !update.notes.isEmpty {
                        ScrollView { Text(update.notes).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 120)
                    }
                    Text(L10n.text("Download size: {0}", ByteCountFormatter.string(fromByteCount: update.size, countStyle: .file)))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(L10n.text("The DMG will open after verification. Quit SimFlutDock, then drag the app to Applications and confirm replacement."))
                        .font(.callout).foregroundStyle(.secondary)
                    Button(L10n.text("Download Update")) { updater.download(update) }
                        .keyboardShortcut(.defaultAction)
                case .downloading:
                    ProgressView(L10n.text("Downloading and verifying the installer…"))
                    Button(L10n.text("Cancel Download")) { updater.cancel() }
                case .ready(let url):
                    Text(L10n.text("The installer is ready."))
                    Text(L10n.text("Quit SimFlutDock, drag the app from the DMG to Applications, confirm replacement, then launch it from Applications. Running Flutter sessions will be stopped when you quit."))
                        .font(.callout)
                    HStack {
                        Button(L10n.text("Open Installer")) { updater.openInstaller(url) }
                        Button(L10n.text("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Button(L10n.text("Quit to Install")) { NSApp.terminate(nil) }
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
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L10n.text("Automatically check for updates"), isOn: $updater.automaticallyChecks)
                .toggleStyle(.switch)
            Text(L10n.text("Checks at launch, at most once a day. Downloads only with your permission."))
                .font(.callout).foregroundStyle(.secondary)
            Button(L10n.text("Check for Updates…")) { updater.check() }
        }.padding(18)
    }
}

import AppKit
import SwiftUI
import Combine
import ServiceManagement
import FluttiosCore
import ImageIO
import UniformTypeIdentifiers

@MainActor final class BackgroundLaunch: ObservableObject {
    @Published private(set) var status = SMAppService.Status.notRegistered
    @Published private(set) var error: String?
    private let service = SMAppService.loginItem(identifier: "com.fluttios.helper")
    var enabled: Bool { status == .enabled }
    var title: String {
        switch status {
        case .enabled: return L10n.text("Helper enabled")
        case .requiresApproval: return L10n.text("Allow the helper in System Settings → General → Login Items")
        case .notFound: return L10n.text("Helper not found. Open the built Fluttios.app from /Applications.")
        default: return L10n.text("Automatic launch disabled")
        }
    }
    init() { refresh() }
    func refresh() { status = service.status }
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try service.register() }
            else {
                try service.unregister()
                DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.fluttios.helper.quit"), object: nil, userInfo: nil, deliverImmediately: true)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
        refresh()
    }
    func systemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor final class AppModel: ObservableObject {
    @Published var language = L10n.language {
        didSet { if language != L10n.language { L10n.language = language } }
    }
    @Published private(set) var languageRevision = 0
    var languageDidChange: () -> Void = {}
    let store = ProjectStore()
    let simulators = SimulatorService()
    let tracker = SimulatorWindowTracker()
    let background = BackgroundLaunch()
    let manager: SessionManager
    @Published var globalSDK: String = UserDefaults.standard.string(forKey: "globalSDK") ?? "" {
        didSet { UserDefaults.standard.set(globalSDK, forKey: "globalSDK") }
    }
    @Published var freePanel = UserDefaults.standard.bool(forKey: "attachedPanelBehaviorV2") ? UserDefaults.standard.bool(forKey: "freePanel") : false {
        didSet { UserDefaults.standard.set(freePanel, forKey: "freePanel") }
    }
    @Published var attachmentStatus = ""
    @Published var panelWidth: CGFloat = 420
    @Published var actualPanelSide: PanelSide?
    @Published var panelSide = PanelSide(rawValue: UserDefaults.standard.string(forKey: "panelSide") ?? "") ?? .above {
        didSet { UserDefaults.standard.set(panelSide.rawValue, forKey: "panelSide") }
    }
    @Published private(set) var pinnedSimulatorIDs = Set(UserDefaults.standard.stringArray(forKey: "pinnedSimulatorIDs") ?? []) {
        didSet { UserDefaults.standard.set(pinnedSimulatorIDs.sorted(), forKey: "pinnedSimulatorIDs") }
    }
    @Published private(set) var bootingSimulatorIDs: Set<String> = []
    @Published private(set) var simulatorBootError: String?
    @Published var message: String?
    @Published private(set) var simulatorToolBusy = false
    @Published private(set) var simulatorToolResult: String?
    @Published private(set) var simulatorToolProjectID: UUID?
    @Published var checkingTools = false
    var showSettings: () -> Void = {}
    var showLogs: () -> Void = {}
    var showPanel: () -> Void = {}
    var hidePanel: () -> Void = {}
    var quitApp: () -> Void = {}
    var dragPanel: (NSEvent) -> Void = { _ in }
    var bindWindow: (UUID) -> Void = { _ in }
    var resetPanel: () -> Void = {}
    private var subscriptions = Set<AnyCancellable>()
    @Published private(set) var projectIcons: [String: NSImage] = [:]
    private var loadedIconPaths = Set<String>()
    private var iconLoadTask: Task<Void, Never>?

    func projectImage(_ project: Project?) -> Image {
        if let project, let icon = projectIcons[project.path] { return Image(nsImage: icon) }
        return Image(systemName: "folder")
    }

    private func loadProjectIcons(_ paths: [String]) {
        iconLoadTask?.cancel()
        let retainedPaths = Set(paths)
        projectIcons = projectIcons.filter { retainedPaths.contains($0.key) }
        loadedIconPaths.formIntersection(retainedPaths)
        let missing = paths.filter { !loadedIconPaths.contains($0) }
        guard !missing.isEmpty else { return }
        iconLoadTask = Task { [weak self] in
            let images = await Task.detached(priority: .utility) {
                var images: [String: Data] = [:]
                for path in missing {
                    for url in ProjectIconSource.candidates(projectPath: path) {
                        // Decode only a menu-sized thumbnail, off the UI thread.
                        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceThumbnailMaxPixelSize: 64,
                                kCGImageSourceCreateThumbnailWithTransform: true
                              ] as CFDictionary) else { continue }
                        let data = NSMutableData()
                        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { continue }
                        CGImageDestinationAddImage(destination, thumbnail, nil)
                        guard CGImageDestinationFinalize(destination) else { continue }
                        images[path] = data as Data
                        break
                    }
                }
                return images
            }.value
            guard !Task.isCancelled, let self else { return }
            for (path, data) in images {
                guard let image = NSImage(data: data) else { continue }
                image.size = NSSize(width: 18, height: 18)
                self.projectIcons[path] = image
            }
            self.loadedIconPaths.formUnion(missing)
        }
    }
    var selectedSession: FlutterSession? { store.selectedID.flatMap { manager.sessions[$0] } }
    var verticalPanel: Bool { actualPanelSide?.isVertical == true }
    var panelHeight: CGFloat { verticalPanel ? 374 : horizontalPanelHeight }
    var horizontalPanelHeight: CGFloat { selectedSession?.state.isBusy == true ? 70 : 48 }
    var selectedDevice: SimulatorDevice? {
        if let session = selectedSession, session.hasWork { return session.device }
        return simulators.devices.first { $0.id == store.selected?.deviceID }
    }
    var simulatorToolDevice: SimulatorDevice? {
        guard let device = selectedDevice else { return nil }
        return simulators.devices.first { $0.id == device.id } ?? device
    }
    var physicalTarget: Bool { selectedDevice?.isPhysical ?? store.selected?.deviceIsPhysical ?? false }
    var standaloneTarget: Bool {
        if let device = selectedDevice { return !device.isIOSSimulator }
        return physicalTarget || (store.selected?.devicePlatform.map { $0 != "ios" } ?? false)
    }
    var standalonePanel: Bool { freePanel || standaloneTarget }
    var launchMode: LaunchMode {
        if let session = selectedSession, session.hasWork { return session.launchProject?.launch.mode ?? .debug }
        return store.selected?.launch.mode ?? .debug
    }
    func refreshDevices() async { await simulators.refresh(project: store.selected, globalSDK: globalSDK) }
    func toggleSimulatorPin(_ device: SimulatorDevice) {
        guard device.isIOSSimulator else { return }
        if !pinnedSimulatorIDs.insert(device.id).inserted { pinnedSimulatorIDs.remove(device.id) }
    }
    func bootSimulator(_ device: SimulatorDevice) {
        guard device.isIOSSimulator, device.isAvailable, device.state == "Shutdown",
              bootingSimulatorIDs.insert(device.id).inserted else { return }
        simulatorBootError = nil
        Task {
            defer { bootingSimulatorIDs.remove(device.id) }
            do {
                try await simulators.boot(device)
                // A refresh already in flight may contain the pre-boot state.
                while simulators.refreshing { try await Task.sleep(for: .milliseconds(100)) }
                await refreshDevices()
            } catch {
                simulatorBootError = L10n.text("Could not start {0}: {1}", "\(device.name)", "\(error.localizedDescription)")
            }
        }
    }
    func chooseDevice(_ device: SimulatorDevice?) {
        guard var project = store.selected, !(selectedSession?.hasWork ?? false) else { return }
        project.deviceID = device?.id; project.deviceIsPhysical = device?.isPhysical; project.devicePlatform = device?.targetPlatform
        if !project.launch.mode.supports(device) { project.launch.setMode(.debug) }
        store.update(project); tracker.refresh()
    }
    func chooseLaunchMode(_ mode: LaunchMode) {
        guard var project = store.selected, !(selectedSession?.hasWork ?? false), mode.supports(selectedDevice) else { return }
        project.launch = project.launch.usingProjectDefaults(mode: mode)
        store.update(project)
    }
    init() {
        if !UserDefaults.standard.bool(forKey: "attachedPanelBehaviorV2") {
            UserDefaults.standard.set(true, forKey: "attachedPanelBehaviorV2")
            UserDefaults.standard.set(false, forKey: "freePanel")
            UserDefaults.standard.removeObject(forKey: "panelOffsetX")
            UserDefaults.standard.removeObject(forKey: "panelOffsetY")
        }
        manager = SessionManager(simulators: simulators)
        for notification in [L10n.didChange, NSLocale.currentLocaleDidChangeNotification] {
            NotificationCenter.default.publisher(for: notification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.language = L10n.language
                    self.languageRevision += 1
                    self.tracker.refresh()
                    self.languageDidChange()
                }.store(in: &subscriptions)
        }
        store.$projects.map { $0.map(\.path) }.removeDuplicates()
            .sink { [weak self] in self?.loadProjectIcons($0) }.store(in: &subscriptions)
        for publisher in [store.objectWillChange.eraseToAnyPublisher(), simulators.objectWillChange.eraseToAnyPublisher(),
                          tracker.objectWillChange.eraseToAnyPublisher(), manager.objectWillChange.eraseToAnyPublisher(), background.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        }
        Task { await refreshDevices() }
    }
    func select(_ project: Project) {
        store.select(project.id); tracker.refresh()
        Task { await refreshDevices() }
        Task {
            await manager.foreground(project.id)
            guard store.selectedID == project.id else { return }
            let windows = tracker.matching(selectedDevice, knownDevices: simulators.devices)
            if !standalonePanel, windows.count == 1 { tracker.raise(windows[0]) }
        }
    }
    func openProject(replacing: UUID? = nil) {
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true
        picker.prompt = L10n.text("Open Project"); picker.message = L10n.text("Select a Flutter project folder.")
        picker.begin { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            MainActor.assumeIsolated {
                do {
                    _ = try self?.store.open(url, replacing: replacing)
                    Task { await self?.refreshDevices() }
                } catch { self?.message = error.localizedDescription }
            }
        }
    }
    func chooseSDK(_ completion: @escaping (String) -> Void) {
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.showsHiddenFiles = true
        picker.message = L10n.text("Select the Flutter SDK (the folder containing bin/flutter). For FVM, select .fvm/flutter_sdk or a specific version folder.")
        picker.begin { response in
            if response == .OK, let url = picker.url { MainActor.assumeIsolated { completion(url.path) } }
        }
    }
    func run() {
        guard !simulatorToolBusy else {
            message = L10n.text("Wait for the simulator action to finish before pressing Run.")
            return
        }
        guard var project = store.selected else { openProject(); return }
        if let id = project.deviceID, !simulators.devices.contains(where: { $0.id == id }) {
            message = L10n.text("The saved device is unavailable. Refresh the list and select a device in the panel. For iPhone / iPad, check the connection, trust this Mac, and enable Developer Mode."); return
        }
        let device = simulators.devices.first { $0.id == project.deviceID } ?? AutomaticDeviceSelection.device(from: simulators.devices)
        guard let device else { message = L10n.text("Select a connected iPhone / iPad, or install an iOS Simulator in Xcode and refresh the device list in the panel."); return }
        project.launch = project.launch.usingProjectDefaults()
        store.update(project)
        manager.run(project: project, device: device, globalSDK: globalSDK)
    }
    func restart(full: Bool) {
        guard let id = store.selectedID, !manager.foregroundIDs.contains(id) else { return }
        Task {
            await manager.foreground(id)
            manager.sessions[id]?.restart(full: full)
        }
    }
    func openProjectFolder(_ project: Project) {
        guard NSWorkspace.shared.open(URL(fileURLWithPath: project.path, isDirectory: true)) else {
            simulatorToolProjectID = project.id
            simulatorToolResult = L10n.text("Could not open the project folder. Check its location in settings.")
            return
        }
    }
    enum ProjectAction { case dataFolder, resetPermissions }
    var canClearSavedProjects: Bool {
        !store.projects.isEmpty && !manager.hasActiveSessions && !simulatorToolBusy && !manager.shuttingDown
    }
    func removeSavedProject(_ projectID: UUID) {
        guard manager.sessions[projectID]?.hasWork != true, !simulatorToolBusy, !manager.shuttingDown else { return }
        store.remove(projectID)
    }
    func clearSavedProjects() {
        guard canClearSavedProjects else { return }
        store.clearSavedProjects()
    }
    func openProjectDataFolder(_ projectID: UUID) { projectAction(.dataFolder, projectID: projectID) }
    func resetProjectPermissions(_ projectID: UUID) { projectAction(.resetPermissions, projectID: projectID) }
    private func projectAction(_ action: ProjectAction, projectID: UUID) {
        guard !simulatorToolBusy, let project = store.projects.first(where: { $0.id == projectID }) else { return }
        let session = manager.sessions[project.id]
        let active = session?.hasWork == true
        let deviceID = active ? session?.device?.id : project.deviceID
        let launchProject = active ? session?.launchProject ?? project : project
        let knownBundle = active ? session?.bundleID : nil
        simulatorToolProjectID = project.id; simulatorToolResult = nil
        guard let deviceID else {
            simulatorToolResult = L10n.text("Select an iOS Simulator for this project in settings.")
            return
        }
        if case .resetPermissions = action, active {
            simulatorToolResult = L10n.text("Press Stop for this app before resetting permissions.")
            return
        }
        guard !active || session?.state == .running else {
            simulatorToolResult = L10n.text("Wait for the Flutter operation to finish, then try again.")
            return
        }
        simulatorToolBusy = true
        Task {
            defer { simulatorToolBusy = false }
            do {
                let device = try await simulators.currentSimulator(id: deviceID)
                let bundle: String
                if let knownBundle { bundle = knownBundle }
                else { bundle = try await simulators.bundleIdentifier(launchProject, device: device) }
                switch action {
                case .dataFolder:
                    let url = try await simulators.dataContainer(bundleID: bundle, device: device)
                    _ = try await NSWorkspace.shared.open([url],
                        withApplicationAt: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                        configuration: NSWorkspace.OpenConfiguration())
                    simulatorToolResult = L10n.text("Data folder opened in Finder.")
                case .resetPermissions:
                    guard manager.sessions[project.id]?.hasWork != true,
                          manager.conflictingProject(bundleID: bundle, deviceID: device.id, excluding: project.id) == nil else {
                        throw FluttiosError.message(L10n.text("Press Stop for the app on this simulator before resetting permissions."))
                    }
                    try await simulators.resetPermissions(bundleID: bundle, device: device)
                    simulatorToolResult = L10n.text("Permissions reset. The app will request access again when needed.")
                }
            } catch { simulatorToolResult = error.localizedDescription }
        }
    }
    enum SimulatorAction { case link(String) }
    func simulatorAction(_ action: SimulatorAction) {
        guard !simulatorToolBusy, let project = store.selected else { return }
        simulatorToolProjectID = project.id; simulatorToolResult = nil
        guard let device = simulatorToolDevice, device.isIOSSimulator, device.state == "Booted" else {
            simulatorToolResult = L10n.text("Select a running iOS Simulator in project settings.")
            return
        }
        guard selectedSession?.state.isBusy != true else { return }
        simulatorToolBusy = true
        Task {
            defer { simulatorToolBusy = false }
            do {
                switch action {
                case .link(let url):
                    try await simulators.openDeepLink(url, device: device)
                    simulatorToolResult = L10n.text("Link opened on {0}.", "\(device.name)")
                }
            } catch { simulatorToolResult = error.localizedDescription }
        }
    }
    func checkTools() {
        guard !checkingTools else { return }; checkingTools = true
        Task {
            defer { checkingTools = false }
            do {
                let project = store.selected ?? Project(name: "SDK", path: FileManager.default.homeDirectoryForCurrentUser.path)
                let sdk = try FlutterSDKResolver.resolve(project: project, global: globalSDK)
                let result = try await FlutterSDKResolver.check(sdk)
                message = L10n.text("Flutter and Xcode are available.\n{0}\n{1}", "\(sdk)", "\(result)")
            } catch { message = error.localizedDescription }
            await refreshDevices()
        }
    }
}

import Foundation
import Combine

@MainActor public final class SessionManager: ObservableObject {
    @Published public private(set) var shuttingDown = false
    @Published public private(set) var foregroundIDs: Set<UUID> = []
    @Published public private(set) var sessions: [UUID: FlutterSession] = [:]
    private var observations: [UUID: AnyCancellable] = [:]
    public let simulators: SimulatorService
    public init(simulators: SimulatorService) { self.simulators = simulators }
    public var hasActiveSessions: Bool { sessions.values.contains { $0.hasWork } }
    public func session(for id: UUID) -> FlutterSession {
        if let session = sessions[id] { return session }
        let session = FlutterSession(projectID: id); sessions[id] = session
        observations[id] = session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        return session
    }
    public func conflictingProject(bundleID: String, deviceID: String, excluding: UUID) -> UUID? {
        sessions.values.first { $0.id != excluding && $0.hasWork && $0.bundleID == bundleID && $0.device?.id == deviceID }?.id
    }
    public func run(project: Project, device: SimulatorDevice, globalSDK: String?) {
        guard !shuttingDown else { return }
        let session = session(for: project.id)
        guard session.canRun else { return }
        session.prepare(project: project, device: device)
        let task = Task { [weak self, weak session] in
            guard let self, let session else { return }
            do {
                try ProjectStore.validate(URL(fileURLWithPath: project.path))
                _ = try project.launch.validatedArguments(for: device)
                let sdk = try FlutterSDKResolver.resolve(project: project, global: globalSDK)
                session.setPreparationStage(L10n.text("Checking Flutter SDK"))
                session.append(L10n.text("Checking SDK: {0}", "\(sdk)"))
                _ = try await FlutterSDKResolver.check(sdk)
                try Task.checkCancellation()
                session.setPreparationStage(device.targetPlatform == "ios" ? L10n.text("Reading Xcode settings") : L10n.text("Preparing project"))
                let bundleID = try await self.simulators.bundleIdentifier(project, device: device)
                try Task.checkCancellation()
                if let conflict = self.conflictingProject(bundleID: bundleID, deviceID: device.id, excluding: project.id) {
                    let name = self.sessions[conflict]?.launchProject?.name ?? L10n.text("another project")
                    throw SimFlutDockError.message(L10n.text("{0} is already using {1} on {2}. Select another device in the panel.", "\(name)", "\(bundleID)", "\(device.name)"))
                }
                session.reserve(bundleID: bundleID)
                session.setPreparationStage(device.isIOSSimulator ? L10n.text("Starting simulator") : L10n.text("Preparing device launch"))
                try await self.simulators.boot(device)
                try Task.checkCancellation()
                try session.start(executable: sdk, project: project, device: device, bundleID: bundleID)
                await self.simulators.refresh(project: project, globalSDK: globalSDK)
            } catch { session.launchFailed(error) }
        }
        session.setPreparationTask(task)
    }
    public func foreground(_ id: UUID) async {
        guard !foregroundIDs.contains(id), let session = sessions[id], session.state == .running, let device = session.device, let bundleID = session.bundleID else { return }
        guard device.isIOSSimulator else { return }
        foregroundIDs.insert(id); defer { foregroundIDs.remove(id) }
        do { try await simulators.foreground(deviceID: device.id, bundleID: bundleID) }
        catch { session.append(L10n.text("Could not bring the app to the foreground: {0}", "\(error.localizedDescription)"), error: true) }
    }
    public func stopAll() { sessions.values.filter { $0.hasWork }.forEach { $0.stop() } }
    public func waitForStop() async {
        shuttingDown = true
        stopAll()
        while hasActiveSessions { try? await Task.sleep(nanoseconds: 100_000_000) }
    }
}

import Combine
import Foundation

public struct SessionKey: Hashable {
    public let projectID: UUID
    public let deviceID: String

    public init(projectID: UUID, deviceID: String) {
        self.projectID = projectID
        self.deviceID = deviceID
    }
}

@MainActor public final class SessionManager: ObservableObject {
    @Published public private(set) var shuttingDown = false
    @Published public private(set) var foregroundIDs: Set<SessionKey> = []
    @Published public private(set) var rerunningIDs: Set<SessionKey> = []
    @Published public private(set) var sessions: [SessionKey: FlutterSession] = [:]
    private var observations: [SessionKey: AnyCancellable] = [:]
    public let simulators: SimulatorService
    public init(simulators: SimulatorService) { self.simulators = simulators }
    public var hasActiveSessions: Bool { !rerunningIDs.isEmpty || sessions.values.contains { $0.hasWork } }
    public func hasActiveSessions(for projectID: UUID) -> Bool {
        rerunningIDs.contains { $0.projectID == projectID }
            || sessions.contains { $0.key.projectID == projectID && $0.value.hasWork }
    }
    public func session(for projectID: UUID, deviceID: String) -> FlutterSession {
        let key = SessionKey(projectID: projectID, deviceID: deviceID)
        if let session = sessions[key] { return session }
        let session = FlutterSession(projectID: projectID)
        sessions[key] = session
        observations[key] = session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        return session
    }
    public func conflictingProject(bundleID: String, deviceID: String, excluding: UUID) -> UUID? {
        sessions.values.first {
            $0.projectID != excluding && $0.hasWork && $0.bundleID == bundleID && $0.device?.id == deviceID
        }?.projectID
    }
    public func run(project: Project, device: SimulatorDevice, globalSDK: String?) {
        let key = SessionKey(projectID: project.id, deviceID: device.id)
        guard !shuttingDown, !rerunningIDs.contains(key) else { return }
        let session = session(for: project.id, deviceID: device.id)
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
                let version = try await FlutterSDKResolver.check(sdk)
                try Task.checkCancellation()
                session.setFlutterVersion(version)
                session.setPreparationStage(
                    device.targetPlatform == "ios"
                        ? L10n.text("Reading Xcode settings") : L10n.text("Preparing project"))
                let bundleID = try await self.simulators.bundleIdentifier(project, device: device)
                try Task.checkCancellation()
                if let conflict = self.conflictingProject(
                    bundleID: bundleID, deviceID: device.id, excluding: project.id)
                {
                    let key = SessionKey(projectID: conflict, deviceID: device.id)
                    let name = self.sessions[key]?.launchProject?.name ?? L10n.text("another project")
                    throw SimFlutDockError.message(
                        L10n.text(
                            "{0} is already using {1} on {2}. Select another device in the panel.", "\(name)",
                            "\(bundleID)", "\(device.name)"))
                }
                session.reserve(bundleID: bundleID)
                session.setPreparationStage(
                    device.isIOSSimulator ? L10n.text("Starting simulator") : L10n.text("Preparing device launch"))
                try await self.simulators.boot(device)
                try Task.checkCancellation()
                try session.start(executable: sdk, project: project, device: device, bundleID: bundleID)
                await self.simulators.refresh(project: project, globalSDK: globalSDK)
            } catch { session.launchFailed(error) }
        }
        session.setPreparationTask(task)
    }
    public func rerun(project: Project, device: SimulatorDevice, globalSDK: String?) {
        let key = SessionKey(projectID: project.id, deviceID: device.id)
        guard !shuttingDown, !rerunningIDs.contains(key), !foregroundIDs.contains(key),
            let session = sessions[key], session.canRerun
        else { return }
        rerunningIDs.insert(key)
        session.stop()
        Task {
            while session.hasWork { try? await Task.sleep(nanoseconds: 50_000_000) }
            // Remove the reservation and start preparation in the same actor turn.
            rerunningIDs.remove(key)
            guard sessions[key] === session else { return }
            run(project: project, device: device, globalSDK: globalSDK)
        }
    }
    public func foreground(_ id: SessionKey) async {
        guard !foregroundIDs.contains(id), let session = sessions[id], session.state == .running,
            let device = session.device, let bundleID = session.bundleID
        else { return }
        guard device.isIOSSimulator else { return }
        foregroundIDs.insert(id)
        defer { foregroundIDs.remove(id) }
        do { try await simulators.foreground(deviceID: device.id, bundleID: bundleID) } catch {
            session.append(
                L10n.text("Could not bring the app to the foreground: {0}", "\(error.localizedDescription)"),
                error: true)
        }
    }
    public func stopAll() {
        for session in sessions.values where session.hasWork { session.stop() }
    }
    public func removeInactiveSession(_ id: SessionKey) {
        guard sessions[id]?.hasWork != true, !rerunningIDs.contains(id) else { return }
        observations.removeValue(forKey: id)
        sessions.removeValue(forKey: id)
    }
    public func removeInactiveSessions(for projectID: UUID) {
        for key in Array(sessions.keys) where key.projectID == projectID { removeInactiveSession(key) }
    }
    /// Re-enable launches when termination is cancelled after session shutdown.
    public func cancelShutdown() {
        guard !hasActiveSessions else { return }
        shuttingDown = false
    }
    public func waitForStop() async {
        shuttingDown = true
        stopAll()
        while hasActiveSessions { try? await Task.sleep(nanoseconds: 100_000_000) }
    }
}

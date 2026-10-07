import Foundation
import Combine
import Darwin

@MainActor public final class FlutterSession: ObservableObject, Identifiable {
    public let id: UUID
    @Published public private(set) var state: SessionState = .ready
    @Published public private(set) var logs: [LogEntry] = []
    @Published public private(set) var error: String?
    @Published public private(set) var appID: String?
    @Published public private(set) var isAlive = false
    @Published public private(set) var preparing = false
    @Published public private(set) var progressMessage: String?
    private var progressOperations: [(id: String, message: String)] = []
    private var progressFallback: String?
    public private(set) var device: SimulatorDevice?
    public private(set) var bundleID: String?
    public private(set) var launchProject: Project?
    private var process: Process?
    private var input: FileHandle?
    private var stdout: Pipe?, stderr: Pipe?
    private var parser = MachineParser(), errorParser = MachineParser()
    private var dartConsole: DartConsole?
    private var consoleTask: Task<Void, Never>?
    private var dartOut = MachineParser(), dartErr = MachineParser()
    private var scopedConsole = false
    private var consoleReady = false
    private var flutterStarted = false
    private var client: MachineClient?
    private var operation: Task<Void, Never>?
    private var escalation: Task<Void, Never>?
    private var startTimeout: Task<Void, Never>?
    private var intentionalStop = false
    private var generation = UUID()
    public var canRun: Bool { !isAlive && !preparing && state != .stopping }
    public var canStop: Bool { (isAlive || preparing) && state != .stopping && state != .reloading && state != .restarting }
    public var hasWork: Bool { isAlive || preparing || state == .stopping }
    public var canRestart: Bool { state.canRestart && launchProject?.launch.mode == .debug }
    public init(projectID: UUID) { id = projectID }
    public func mainIsolateHeapBytes() async -> Int64? {
        guard state == .running, consoleReady, let console = dartConsole else { return nil }
        let currentGeneration = generation
        let bytes = try? await console.mainIsolateHeapBytes()
        guard generation == currentGeneration, state == .running, !Task.isCancelled else { return nil }
        return bytes
    }
    public func append(_ text: String, error: Bool = false) {
        guard !text.isEmpty else { return }
        logs.append(LogEntry(String(text.prefix(16_384)), isError: error))
        if logs.count > 2000 { logs.removeFirst(logs.count - 2000) }
    }
    public func clearLogs() { logs.removeAll() }
    public func prepare(project: Project, device: SimulatorDevice) {
        launchProject = project; self.device = device; preparing = true; intentionalStop = false
        state = .booting; error = nil; bundleID = nil
        resetProgress(L10n.text("Checking project"))
    }
    public func setPreparationStage(_ message: String) {
        guard preparing, state != .stopping else { return }
        resetProgress(message)
    }
    private func resetProgress(_ message: String? = nil) {
        progressOperations.removeAll(); progressFallback = message; progressMessage = message
    }
    private func handleProgress(_ params: [String: Any]) {
        let message = params["message"] as? String
        if let message, !message.isEmpty, params["finished"] as? Bool != true { append(message) }
        guard state.isBusy, state != .stopping,
              let id = params["id"] as? String else { return }
        if params["finished"] as? Bool == true {
            progressOperations.removeAll { $0.id == id }
        } else if let message, !message.isEmpty {
            progressOperations.removeAll { $0.id == id }
            progressOperations.append((id, message))
        }
        let latest = progressOperations.last?.message ?? progressFallback
        if latest?.hasPrefix("Running Xcode build") == true { progressMessage = L10n.text("Building in Xcode") }
        else if latest?.hasPrefix("Installing and launching") == true { progressMessage = L10n.text("Installing and launching") }
        else { progressMessage = latest }
    }
    public func reserve(bundleID: String) { self.bundleID = bundleID }
    public func launchFailed(_ failure: Error) {
        preparing = false; operation = nil
        resetProgress()
        if intentionalStop || failure is CancellationError { state = .ready; return }
        state = .error; error = failure.localizedDescription; append(failure.localizedDescription, error: true)
    }
    public func setPreparationTask(_ task: Task<Void, Never>) { operation = task }
    public func start(executable: String, project: Project, device: SimulatorDevice, bundleID: String, captureDartConsole: Bool = true) throws {
        guard !isAlive, state != .stopping else { throw CancellationError() }
        signal(SIGPIPE, SIG_IGN)
        // Physical iOS devices can report startPaused=false. Use Flutter's own
        // log stream there, without waiting for a paused isolate or a VM port.
        let captureDartConsole = captureDartConsole && project.launch.mode == .debug && device.isIOSSimulator
        let args = try project.launch.validatedArguments(for: device) + ["-d", device.id] + (captureDartConsole ? ["--start-paused"] : [])
        scopedConsole = captureDartConsole; consoleReady = !captureDartConsole; flutterStarted = false
        dartOut = .init(parseMessages: false); dartErr = .init(parseMessages: false)
        let process = Process(), stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
        let generation = UUID(); self.generation = generation
        self.process = process; self.stdout = stdout; self.stderr = stderr; input = stdin.fileHandleForWriting
        self.device = device; self.bundleID = bundleID; launchProject = project
        parser = .init(); errorParser = .init(); appID = nil; error = nil; intentionalStop = false
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)
        process.environment = FlutterSDKResolver.environment(sdk: executable)
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        client = MachineClient { [weak self] data in
            guard let self, self.isAlive, let input = self.input else { throw SimFlutDockError.exited }
            try input.write(contentsOf: data)
        }
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { [weak self] in self?.consume(data, stderr: false, generation: generation) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { [weak self] in self?.consume(data, stderr: true, generation: generation) }
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { [weak self] in self?.terminated(status: process.terminationStatus, generation: generation) }
        }
        do { try process.run() }
        catch {
            stdout.fileHandleForReading.readabilityHandler = nil; stderr.fileHandleForReading.readabilityHandler = nil
            client?.close(error: error); input = nil; self.process = nil; throw error
        }
        isAlive = true; preparing = false; operation = nil; state = .building
        resetProgress(L10n.text("Building and launching app"))
        append("Run: \(project.name) • \(device.name) • \(project.launch.mode.title) • \(bundleID)")
        startTimeout?.cancel()
        startTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
            guard let self, self.generation == generation, self.state == .building else { return }
            self.error = L10n.text("Flutter did not finish launching within 10 minutes. Stop the session and check the logs.")
            self.append(self.error!, error: true)
        }
    }
    private func consume(_ data: Data, stderr: Bool, generation: UUID) {
        guard self.generation == generation else { return }
        let messages = stderr ? errorParser.feed(data) : parser.feed(data)
        for message in messages { handle(message, isError: stderr) }
    }
    public func handle(_ output: MachineOutput, isError: Bool = false) {
        switch output {
        case .text(let text):
            // Flutter simulator log readers filter by executable name, which is often
            // Runner in every project. Dart console is read from the per-app VM instead.
            if scopedConsole && (text.hasPrefix("flutter:") || text.contains(":flutter/") || text.hasPrefix("[IMPORTANT:flutter")) { return }
            append(text, error: isError)
        case .message(let message):
            if client?.receive(message) == true { return }
            let params = message["params"] as? [String: Any] ?? [:]
            // A process belongs to one project. Ignore events for a different app id.
            if let incoming = params["appId"] as? String, let appID, incoming != appID { return }
            switch message["event"] as? String {
            case "app.start": appID = params["appId"] as? String
            case "app.debugPort":
                guard scopedConsole, dartConsole == nil, let uri = params["wsUri"] as? String, let url = URL(string: uri) else { return }
                let console = DartConsole(); dartConsole = console
                let currentGeneration = generation
                console.onOutput = { [weak self] data, isError in
                    guard let self, self.generation == currentGeneration else { return }
                    let lines = isError ? self.dartErr.feed(data) : self.dartOut.feed(data)
                    for line in lines { if case .text(let text) = line { self.append(text, error: isError) } }
                }
                console.onDisconnect = { [weak self] error in
                    guard let self, self.generation == currentGeneration, self.isAlive, self.state != .stopping else { return }
                    self.state = .disconnected; self.error = L10n.text("Lost connection to Dart VM: {0}. Use Stop and Run.", "\(error.localizedDescription)")
                    self.resetProgress()
                    self.append(self.error!, error: true)
                }
                consoleTask = Task { [weak self] in
                    do {
                        try await console.connectAndResume(url)
                        guard let self, self.generation == currentGeneration, self.state != .stopping else { return }
                        self.consoleReady = true; self.updateStartupState()
                    } catch {
                        guard let self, self.generation == currentGeneration, self.isAlive, self.state != .stopping else { return }
                        self.state = .disconnected; self.error = L10n.text("Could not connect the Dart console: {0}. Use Stop and Run.", "\(error.localizedDescription)")
                        self.resetProgress()
                        self.append(self.error!, error: true); console.close()
                    }
                }
            case "app.started":
                flutterStarted = true
                if state == .building && !consoleReady { resetProgress(L10n.text("Connecting Dart console")) }
                updateStartupState()
            case "app.progress": handleProgress(params)
            case "app.log", "daemon.log":
                let text = params["log"] as? String ?? ""
                if scopedConsole && (text.hasPrefix("flutter:") || text.contains(":flutter/") || text.hasPrefix("[IMPORTANT:flutter")) { return }
                append(text, error: params["error"] as? Bool ?? false)
            case "daemon.logMessage", "daemon.showMessage": append(params["message"] as? String ?? "", error: params["level"] as? String == "error")
            case "app.warning": append(params["warning"] as? String ?? "")
            case "app.stop":
                appID = nil; client?.close(); startTimeout?.cancel()
                resetProgress()
                if !intentionalStop { state = .disconnected; error = L10n.text("The app disconnected. Stop the remaining process or use Run after it exits.") }
                if process?.isRunning == true { process?.terminate(); scheduleEscalation() }
            default: break
            }
        }
    }
    private func updateStartupState() {
        if flutterStarted && consoleReady && state == .building { startTimeout?.cancel(); state = .running; resetProgress() }
    }
    public func restart(full: Bool) {
        guard canRestart, let appID, let client else { return }
        state = full ? .restarting : .reloading; error = nil
        resetProgress(state.title)
        operation = Task { [weak self] in
            do {
                let response = try await client.request("app.restart", params: ["appId": appID, "fullRestart": full, "pause": false, "reason": "manual", "debounce": false], timeout: 90)
                if let result = response["result"] as? [String: Any], let code = result["code"] as? Int, code != 0 {
                    throw SimFlutDockError.message(result["message"] as? String ?? L10n.text("Flutter could not update the app."))
                }
                guard let self, self.isAlive, self.state != .stopping else { return }
                if full { try await self.dartConsole?.resumePausedIsolates() }
                guard self.isAlive, self.state != .stopping else { return }
                self.state = .running; self.resetProgress(); self.append(full ? L10n.text("Hot restart completed.") : L10n.text("Hot reload completed."))
            } catch {
                guard let self, self.isAlive, self.state != .stopping else { return }
                if case SimFlutDockError.timeout = error { self.state = .disconnected } else { self.state = .running }
                self.error = error.localizedDescription; self.append(error.localizedDescription, error: true)
                self.resetProgress()
            }
            self?.operation = nil
        }
    }
    public func stop() {
        guard hasWork, state != .stopping else { return }
        let previousOperation = operation
        let waitForCommand = state == .reloading || state == .restarting
        intentionalStop = true; state = .stopping
        resetProgress(L10n.text("Stopping app"))
        if !waitForCommand { operation?.cancel() }
        operation = nil; startTimeout?.cancel(); consoleTask?.cancel(); dartConsole?.close()
        if !isAlive {
            // Keep the reservation until the cancelled preparation actually unwinds.
            return
        }
        scheduleEscalation()
        operation = Task { [weak self] in
            if waitForCommand { await previousOperation?.value }
            guard let self, self.isAlive else { return }
            if let appID = self.appID, let client = self.client {
                do { _ = try await client.request("app.stop", params: ["appId": appID], timeout: 8) }
                catch { if self.isAlive && self.appID != nil { self.append(error.localizedDescription, error: true) } }
            } else if self.process?.isRunning == true { self.process?.terminate() }
        }
    }
    private func scheduleEscalation() {
        escalation?.cancel()
        let generation = generation
        escalation = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            guard let self, self.generation == generation, let process = self.process, process.isRunning else { return }
            self.append(L10n.text("Flutter did not exit normally; terminating the process owned by this session."), error: true)
            process.terminate()
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            if self.generation == generation && process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    private func terminated(status: Int32, generation: UUID) {
        guard self.generation == generation else { return }
        stdout?.fileHandleForReading.readabilityHandler = nil; stderr?.fileHandleForReading.readabilityHandler = nil
        for output in parser.finish() { handle(output) }
        for output in errorParser.finish() { handle(output, isError: true) }
        consoleTask?.cancel(); consoleTask = nil; dartConsole?.close(); dartConsole = nil
        for line in dartOut.finish() { if case .text(let text) = line { append(text) } }
        for line in dartErr.finish() { if case .text(let text) = line { append(text, error: true) } }
        client?.close(); client = nil; input = nil; process = nil; stdout = nil; stderr = nil
        operation?.cancel(); operation = nil; escalation?.cancel(); escalation = nil; startTimeout?.cancel()
        isAlive = false; preparing = false; appID = nil
        resetProgress()
        if intentionalStop { state = .ready; error = nil }
        else {
            state = status == 0 ? .disconnected : .error
            error = L10n.text("Flutter exited (code {0}). Check the logs and press Run.", "\(status)")
            append(error!, error: true)
        }
        append(L10n.text("Process exited: {0}.", "\(status)"))
    }
}

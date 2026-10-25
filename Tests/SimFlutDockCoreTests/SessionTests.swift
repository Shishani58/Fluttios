import Combine
import XCTest

@testable import SimFlutDockCore

final class SessionTests: XCTestCase {
    @MainActor func testAndroidBuildStagesAndInstallationFailuresAreVisible() async throws {
        let device = SimulatorDevice(
            udid: "ANDROID", name: "Pixel", state: "Available", targetPlatform: "android-arm64", isEmulator: false)
        var project = Project(name: "Android", path: "/tmp")
        project.launch.setMode(.release)
        let session = FlutterSession(projectID: project.id)
        for failure in ["INSTALL_FAILED_VERSION_DOWNGRADE", "INSTALL_FAILED_USER_RESTRICTED", "other failure"] {
            try session.start(
                executable: "/usr/bin/false", project: project, device: device, bundleID: "com.test.android",
                captureDartConsole: false)
            session.handle(
                .message([
                    "event": "app.progress",
                    "params": ["id": "gradle", "message": "Running Gradle task 'assembleRelease'..."],
                ]))
            XCTAssertEqual(session.progressMessage, L10n.text("Building Android app"))
            session.handle(
                .message([
                    "event": "app.log",
                    "params": ["log": "Installing build/app/outputs/flutter-apk/app-release.apk..."],
                ]))
            XCTAssertEqual(session.progressMessage, L10n.text("Installing on Android device"))
            // Flutter can retry after a downgrade, then fail for a different reason.
            session.handle(.text("Failure [INSTALL_FAILED_VERSION_DOWNGRADE]"))
            if failure == "other failure" {
                session.handle(.message(["event": "app.started", "params": [:]]))
            }
            session.handle(.text("Failure [\(failure)]"))
            try await wait { !session.isAlive }
            XCTAssertEqual(session.state, .error)
            switch failure {
            case "INSTALL_FAILED_VERSION_DOWNGRADE":
                XCTAssertEqual(
                    session.error,
                    L10n.text(
                        "Android rejected an older app version. Increase the project's versionCode above the installed version, then press Run."
                    ))
            case "INSTALL_FAILED_USER_RESTRICTED":
                XCTAssertEqual(
                    session.error,
                    L10n.text(
                        "Android did not allow installation. Unlock the device and confirm the installation prompt, then press Run."
                    ))
            default:
                XCTAssertEqual(
                    session.error, L10n.text("Flutter exited (code {0}). Check the logs and press Run.", "1"))
            }
        }
    }
    @MainActor func testRestartFailureCannotRestoreRunningStateAfterDisconnect() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".py")
        defer { try? FileManager.default.removeItem(at: script) }
        try """
        #!/usr/bin/python3
        import signal, time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        print('[{"event":"app.start","params":{"appId":"app"}},{"event":"app.started"}]', flush=True)
        time.sleep(1)
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let session = FlutterSession(projectID: UUID())
        try session.start(
            executable: script.path, project: Project(name: "Disconnect", path: "/tmp"),
            device: SimulatorDevice(udid: "D", name: "Test", state: "Booted"),
            bundleID: "com.test.disconnect", captureDartConsole: false)
        defer { session.stop() }
        try await wait { session.state == .running }
        let runningAgain = expectation(description: "An obsolete restart must not restore Running")
        runningAgain.isInverted = true
        let observation = session.$state.dropFirst().sink { state in
            if state == .running { runningAgain.fulfill() }
        }
        session.restart(full: false)
        session.handle(.message(["event": "app.stop", "params": ["appId": "app"]]))
        // The process stays alive briefly, so isAlive alone cannot reject this stale completion.
        await fulfillment(of: [runningAgain], timeout: 0.2)
        withExtendedLifetime(observation) {}
        try await wait { !session.isAlive }
    }

    @MainActor func testCancelledShutdownAllowsNewLaunches() async throws {
        let manager = SessionManager(simulators: SimulatorService())
        await manager.waitForStop()
        XCTAssertTrue(manager.shuttingDown)
        manager.cancelShutdown()
        XCTAssertFalse(manager.shuttingDown)
        let project = Project(name: "Missing project", path: "/nonexistent/SimFlutDock-test")
        manager.run(project: project, device: SimulatorDevice(udid: "D", name: "Test", state: "Booted"), globalSDK: nil)
        let session = try XCTUnwrap(manager.sessions[SessionKey(projectID: project.id, deviceID: "D")])
        try await wait { !session.hasWork }
        XCTAssertEqual(session.state, .error)
    }
    @MainActor func testProgressTracksNestedOperationsAndIgnoresOtherApps() {
        let session = FlutterSession(projectID: UUID())
        session.prepare(
            project: Project(name: "A", path: "/tmp"),
            device: SimulatorDevice(udid: "SIM", name: "iPhone", state: "Booted"))
        session.setPreparationStage("Проверка Flutter SDK")
        XCTAssertEqual(session.progressMessage, "Проверка Flutter SDK")
        session.handle(.message(["event": "app.start", "params": ["appId": "owned"]]))
        func progress(_ id: String, message: String? = nil, finished: Bool = false, app: String = "owned") {
            var params: [String: Any] = ["appId": app, "id": id, "finished": finished]
            if let message { params["message"] = message }
            session.handle(.message(["event": "app.progress", "params": params]))
        }
        progress("xcode", message: "Running Xcode build...")
        XCTAssertEqual(session.progressMessage, L10n.text("Building in Xcode"))
        progress("install", message: "Installing and launching...")
        XCTAssertEqual(session.progressMessage, L10n.text("Installing and launching"))
        progress("other", message: "Other app", app: "foreign")
        progress("missing", finished: true)
        progress("xcode", finished: true)
        XCTAssertEqual(session.progressMessage, L10n.text("Installing and launching"))
        progress("install", finished: true)
        XCTAssertEqual(session.progressMessage, "Проверка Flutter SDK")
        XCTAssertTrue(session.logs.contains { $0.text == "Running Xcode build..." })
        session.stop()
        progress("late", message: "Late build event")
        XCTAssertEqual(session.progressMessage, L10n.text("Stopping app"))
        session.launchFailed(CancellationError())
        XCTAssertNil(session.progressMessage)
        XCTAssertEqual(session.state, .ready)
        session.prepare(
            project: Project(name: "B", path: "/tmp"),
            device: SimulatorDevice(udid: "SIM", name: "iPhone", state: "Booted"))
        session.launchFailed(SimFlutDockError.message("Build failed"))
        XCTAssertNil(session.progressMessage)
    }
    @MainActor func testProgressClearsOnStartupAndProcessExit() async throws {
        let session = FlutterSession(projectID: UUID())
        try session.start(
            executable: "/usr/bin/true", project: Project(name: "A", path: "/tmp"),
            device: SimulatorDevice(udid: "SIM", name: "iPhone", state: "Booted"), bundleID: "com.test.progress",
            captureDartConsole: false)
        XCTAssertNotNil(session.progressMessage)
        session.handle(
            .message(["event": "app.progress", "params": ["id": "build", "message": "Running Xcode build..."]]))
        session.handle(.message(["event": "app.started", "params": [:]]))
        XCTAssertEqual(session.state, .running)
        XCTAssertNil(session.progressMessage)
        session.handle(.message(["event": "app.progress", "params": ["id": "late", "message": "Late build event"]]))
        XCTAssertNil(session.progressMessage)
        try await wait { !session.isAlive }
        XCTAssertNil(session.progressMessage)
    }
    private func fixture() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".py")
        let script = """
            #!/usr/bin/python3
            import json, sys
            def send(msg): print(json.dumps([msg]), flush=True)
            send({"event":"app.start","params":{"appId":"app"}})
            send({"event":"app.log","params":{"appId":"app","log":"arguments:"+json.dumps(sys.argv[1:])}})
            send({"event":"app.started","params":{"appId":"app"}})
            for line in sys.stdin:
                command=json.loads(line)[0]
                send({"event":"app.log","params":{"appId":"app","log":command["method"]+str(command.get("params",{}).get("fullRestart",False))}})
                send({"id":command["id"],"result":{"code":0}})
                if command["method"]=="app.stop":
                    send({"event":"app.stop","params":{"appId":"app"}})
                    break
            """
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { throw SimFlutDockError.timeout("test") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    @MainActor func testIndependentProcessesCommandRoutingStateAndStopRun() async throws {
        let script = try fixture()
        defer { try? FileManager.default.removeItem(at: script) }
        let manager = SessionManager(simulators: SimulatorService())
        let a = Project(name: "A", path: "/tmp")
        let b = Project(name: "B", path: "/tmp")
        let device = SimulatorDevice(udid: "D", name: "Test", state: "Booted")
        let sa = manager.session(for: a.id, deviceID: device.id)
        let sb = manager.session(for: b.id, deviceID: device.id)
        try sa.start(
            executable: script.path, project: a, device: device, bundleID: "com.test.a", captureDartConsole: false)
        try sb.start(
            executable: script.path, project: b, device: device, bundleID: "com.test.b", captureDartConsole: false)
        defer {
            sa.stop()
            sb.stop()
        }
        try await wait { sa.state == .running && sb.state == .running }
        XCTAssertFalse(sa.canRun)
        XCTAssertTrue(sa.canStop)
        sa.restart(full: false)
        XCTAssertEqual(sa.state, .reloading)
        sa.restart(full: true)  // conflicting operation must be ignored
        try await wait { sa.state == .running && sa.logs.contains { $0.text == "app.restartFalse" } }
        XCTAssertFalse(sb.logs.contains { $0.text.contains("app.restart") })
        XCTAssertFalse(sa.logs.contains { $0.text == "app.restartTrue" })
        sb.restart(full: true)
        try await wait { sb.state == .running && sb.logs.contains { $0.text == "app.restartTrue" } }
        XCTAssertEqual(manager.conflictingProject(bundleID: "com.test.a", deviceID: "D", excluding: b.id), a.id)
        XCTAssertNil(manager.conflictingProject(bundleID: "com.test.a", deviceID: "D2", excluding: b.id))
        sa.stop()
        XCTAssertEqual(sa.state, .stopping)
        try await wait { sa.canRun }
        XCTAssertTrue(sb.isAlive)
        XCTAssertEqual(sa.state, .ready)
        try sa.start(
            executable: script.path, project: a, device: device, bundleID: "com.test.a", captureDartConsole: false)
        try await wait { sa.state == .running }
        let shutdown = Task { await manager.waitForStop() }
        while !manager.shuttingDown { await Task.yield() }
        let late = Project(name: "Late launch", path: "/tmp")
        manager.run(project: late, device: device, globalSDK: nil)
        XCTAssertNil(manager.sessions[SessionKey(projectID: late.id, deviceID: device.id)])
        await shutdown.value
        XCTAssertFalse(manager.hasActiveSessions)
    }
    @MainActor func testRunPreparesSameProjectOnTwoDevices() async throws {
        let manager = SessionManager(simulators: SimulatorService())
        let project = Project(name: "Missing project", path: "/nonexistent/SimFlutDock-test")
        let first = SimulatorDevice(udid: "D1", name: "First", state: "Booted")
        let second = SimulatorDevice(udid: "D2", name: "Second", state: "Booted")
        manager.run(project: project, device: first, globalSDK: nil)
        manager.run(project: project, device: second, globalSDK: nil)
        let a = try XCTUnwrap(manager.sessions[SessionKey(projectID: project.id, deviceID: first.id)])
        let b = try XCTUnwrap(manager.sessions[SessionKey(projectID: project.id, deviceID: second.id)])
        XCTAssertFalse(a === b)
        XCTAssertEqual(a.device?.id, first.id)
        XCTAssertEqual(b.device?.id, second.id)
        XCTAssertTrue(a.preparing && b.preparing)
        manager.run(project: project, device: first, globalSDK: nil)
        XCTAssertEqual(manager.sessions.count, 2)
        try await wait { !manager.hasActiveSessions }
    }
    @MainActor func testRerunWaitsForExitIgnoresDuplicateClicksAndPreservesOtherDevice() async throws {
        let script = try fixture()
        defer { try? FileManager.default.removeItem(at: script) }
        let manager = SessionManager(simulators: SimulatorService())
        // The replacement intentionally fails validation after stopping the old process.
        // This also checks that a failed rebuild releases the Rerun reservation.
        let project = Project(name: "Rerun", path: "/nonexistent/SimFlutDock-rerun-test")
        let first = SimulatorDevice(udid: "D1", name: "First", state: "Booted")
        let second = SimulatorDevice(udid: "D2", name: "Second", state: "Booted")
        let key = SessionKey(projectID: project.id, deviceID: first.id)
        let a = manager.session(for: project.id, deviceID: first.id)
        let b = manager.session(for: project.id, deviceID: second.id)
        var original = project
        original.path = "/tmp"
        try a.start(
            executable: script.path, project: original, device: first, bundleID: "com.test.rerun",
            captureDartConsole: false)
        try b.start(
            executable: script.path, project: original, device: second, bundleID: "com.test.rerun",
            captureDartConsole: false)
        defer { manager.stopAll() }
        try await wait { a.state == .running && b.state == .running }
        let otherLaunch = b.launchID
        var preparations = 0
        let observation = a.$preparing.sink { preparing in
            if preparing {
                preparations += 1
                XCTAssertFalse(a.isAlive, "Rebuild must wait for the previous process to exit")
            }
        }
        manager.rerun(project: project, device: first, globalSDK: nil)
        XCTAssertEqual(a.state, .stopping)
        XCTAssertTrue(manager.rerunningIDs.contains(key))
        manager.rerun(project: project, device: first, globalSDK: nil)
        manager.run(project: project, device: first, globalSDK: nil)
        try await wait { a.state == .error && !manager.rerunningIDs.contains(key) }
        withExtendedLifetime(observation) {}
        XCTAssertEqual(preparations, 1)
        XCTAssertTrue(a.canRun)
        XCTAssertFalse(a.canRerun)
        XCTAssertEqual(a.device?.id, "D1")
        XCTAssertEqual(a.launchProject?.path, "/nonexistent/SimFlutDock-rerun-test")
        XCTAssertTrue(b.isAlive)
        XCTAssertEqual(b.launchID, otherLaunch)
        XCTAssertFalse(b.logs.contains { $0.text.hasPrefix("app.stop") })
        await manager.waitForStop()
    }
    @MainActor func testShutdownCancelsQueuedRerun() async throws {
        let script = try fixture()
        defer { try? FileManager.default.removeItem(at: script) }
        let manager = SessionManager(simulators: SimulatorService())
        let project = Project(name: "Shutdown", path: "/tmp")
        let device = SimulatorDevice(udid: "D", name: "Test", state: "Booted")
        let session = manager.session(for: project.id, deviceID: device.id)
        try session.start(
            executable: script.path, project: project, device: device, bundleID: "com.test.shutdown",
            captureDartConsole: false)
        defer { manager.stopAll() }
        try await wait { session.state == .running }
        let oldLaunch = session.launchID
        manager.rerun(project: project, device: device, globalSDK: nil)
        await manager.waitForStop()
        XCTAssertTrue(manager.rerunningIDs.isEmpty, "Shutdown must drain queued launches before it can be cancelled")
        manager.cancelShutdown()
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(session.launchID, oldLaunch)
        XCTAssertFalse(manager.hasActiveSessions)
    }
    @MainActor func testSameProjectHasIndependentSessionsPerDevice() async throws {
        let script = try fixture()
        defer { try? FileManager.default.removeItem(at: script) }
        let manager = SessionManager(simulators: SimulatorService())
        let project = Project(name: "Same project", path: "/tmp")
        let first = SimulatorDevice(udid: "SIM", name: "Simulator", state: "Booted")
        let second = SimulatorDevice(udid: "PHONE", name: "iPhone", state: "Connected", isPhysical: true)
        let firstKey = SessionKey(projectID: project.id, deviceID: first.id)
        let secondKey = SessionKey(projectID: project.id, deviceID: second.id)
        let a = manager.session(for: project.id, deviceID: first.id)
        try a.start(
            executable: script.path, project: project, device: first, bundleID: "com.test.same",
            captureDartConsole: false)
        defer { manager.stopAll() }
        try await wait { a.state == .running }
        let b = manager.session(for: project.id, deviceID: second.id)
        XCTAssertTrue(b.canRun)
        XCTAssertNotEqual(a.id, b.id)
        try b.start(
            executable: script.path, project: project, device: second, bundleID: "com.test.same",
            captureDartConsole: false)
        try await wait { b.state == .running }
        XCTAssertTrue(manager.sessions[firstKey] === a)
        XCTAssertTrue(manager.sessions[secondKey] === b)
        XCTAssertTrue(manager.session(for: project.id, deviceID: first.id) === a)
        XCTAssertTrue(manager.hasActiveSessions(for: project.id))
        a.restart(full: false)
        try await wait { a.state == .running && a.logs.contains { $0.text == "app.restartFalse" } }
        XCTAssertFalse(b.logs.contains { $0.text.contains("app.restart") })
        b.restart(full: true)
        try await wait { b.state == .running && b.logs.contains { $0.text == "app.restartTrue" } }
        XCTAssertFalse(a.logs.contains { $0.text == "app.restartTrue" })
        a.clearLogs()
        XCTAssertFalse(b.logs.isEmpty)
        a.stop()
        try await wait { a.canRun }
        XCTAssertTrue(b.isAlive)
        manager.removeInactiveSessions(for: project.id)
        XCTAssertNil(manager.sessions[firstKey])
        XCTAssertTrue(manager.sessions[secondKey] === b)
        XCTAssertTrue(manager.hasActiveSessions(for: project.id))
        await manager.waitForStop()
        XCTAssertFalse(manager.hasActiveSessions(for: project.id))
    }
    @MainActor func testUnexpectedExitDoesNotLeaveRememberedLiveSession() async throws {
        let session = FlutterSession(projectID: UUID())
        try session.start(
            executable: "/usr/bin/true", project: Project(name: "Exit", path: "/tmp"),
            device: SimulatorDevice(udid: "D", name: "D", state: "Booted"), bundleID: "com.test.exit",
            captureDartConsole: false)
        try await wait { !session.isAlive }
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertTrue(session.canRun)
        XCTAssertFalse(session.canStop)
    }
    @MainActor func testPhysicalModesStartWithoutInitialPauseAndOnlyDebugAllowsHotRestart() async throws {
        let script = try fixture()
        defer { try? FileManager.default.removeItem(at: script) }
        let phone = SimulatorDevice(udid: "PHONE", name: "iPhone", state: "Подключено", isPhysical: true)
        for mode in LaunchMode.allCases {
            var project = Project(name: "Physical", path: "/tmp")
            project.launch.setMode(mode)
            let manager = SessionManager(simulators: SimulatorService())
            let session = manager.session(for: project.id, deviceID: phone.id)
            try session.start(executable: script.path, project: project, device: phone, bundleID: "com.test.physical")
            defer { session.stop() }
            try await wait { session.state == .running }
            let argumentsLog = try XCTUnwrap(session.logs.first { $0.text.hasPrefix("arguments:") })
            let args = try JSONDecoder().decode(
                [String].self, from: Data(argumentsLog.text.dropFirst("arguments:".count).utf8))
            XCTAssertTrue(args.contains("--" + mode.rawValue))
            XCTAssertFalse(args.contains("--start-paused"))
            XCTAssertEqual(Array(args.suffix(2)), ["-d", phone.id])
            XCTAssertEqual(session.canRestart, mode == .debug)
            if mode == .debug {
                session.restart(full: true)
                try await wait { session.state == .running && session.logs.contains { $0.text == "app.restartTrue" } }
            } else {
                session.restart(full: false)
                session.restart(full: true)
                XCTAssertEqual(session.state, .running)
                XCTAssertFalse(session.logs.contains { $0.text.contains("app.restart") })
            }
            await manager.foreground(SessionKey(projectID: project.id, deviceID: phone.id))
            XCTAssertFalse(
                session.logs.contains {
                    $0.text.contains(
                        L10n.text("Could not bring the app to the foreground: {0}", "").components(separatedBy: ":")[0])
                })
            session.stop()
            try await wait { session.canRun }
            XCTAssertTrue(session.logs.contains { $0.text == "app.stopFalse" })
        }
    }
    @MainActor func testSelectedModeAppliesAfterStopWithoutChangingActiveSession() async throws {
        let script = try fixture()
        defer { try? FileManager.default.removeItem(at: script) }
        let device = SimulatorDevice(
            udid: "ANDROID", name: "Pixel", state: "Booted", targetPlatform: "android-arm64", isEmulator: true)
        var project = Project(name: "Android", path: "/tmp")
        let session = FlutterSession(projectID: project.id)
        defer { session.stop() }
        try session.start(
            executable: script.path, project: project, device: device, bundleID: "com.test.mode",
            captureDartConsole: false)
        try await wait { session.state == .running }
        for mode in [LaunchMode.profile, .release, .debug] {
            project.launch = project.launch.usingProjectDefaults(mode: mode)
            XCTAssertNotEqual(session.launchProject?.launch.mode, mode)
            XCTAssertEqual(session.canRestart, session.launchProject?.launch.mode == .debug)
            session.stop()
            try await wait { session.canRun }
            session.clearLogs()
            try session.start(
                executable: script.path, project: project, device: device, bundleID: "com.test.mode",
                captureDartConsole: false)
            try await wait { session.state == .running }
            XCTAssertEqual(session.launchProject?.launch.mode, mode)
            XCTAssertEqual(session.canRestart, mode == .debug)
            let argumentsLog = try XCTUnwrap(session.logs.first { $0.text.hasPrefix("arguments:") })
            let args = try JSONDecoder().decode(
                [String].self, from: Data(argumentsLog.text.dropFirst("arguments:".count).utf8))
            XCTAssertTrue(args.contains("--" + mode.rawValue))
            XCTAssertEqual(Array(args.suffix(2)), ["-d", device.id])
        }
    }
    @MainActor func testPreparationCancellationAndLogLimit() async throws {
        let session = FlutterSession(projectID: UUID())
        let project = Project(name: "A", path: "/tmp")
        let device = SimulatorDevice(udid: "D", name: "D", state: "Shutdown")
        session.prepare(project: project, device: device)
        session.stop()
        XCTAssertFalse(session.canRun)
        session.launchFailed(CancellationError())
        XCTAssertTrue(session.canRun)
        XCTAssertEqual(session.state, .ready)
        session.prepare(project: project, device: device)
        session.launchFailed(SimFlutDockError.message("failure"))
        XCTAssertEqual(session.state, .error)
        XCTAssertTrue(session.canRun)
        for n in 0..<2200 { session.append("log \(n)") }
        XCTAssertEqual(session.logs.count, 2000)
        session.clearLogs()
        XCTAssertTrue(session.logs.isEmpty)
    }
    func testTimeoutKillsOwnedDescendantAndReturnsPromptly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("child.pid")
        let child =
            "import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); open(\"" + pidFile.path
            + "\",\"w\").write(str(os.getpid())); time.sleep(15)"
        let encoded = Data(child.utf8).base64EncodedString()
        let parent =
            "import subprocess; subprocess.Popen([\"/usr/bin/python3\",\"-c\", \"import base64; exec(base64.b64decode('"
            + encoded + "'))\"]).wait()"
        let begin = Date()
        do {
            _ = try await ToolRunner.run("/usr/bin/python3", ["-c", parent], timeout: 1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error is SimFlutDockError) }
        XCTAssertLessThan(Date().timeIntervalSince(begin), 3)
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8))!
        defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        // A killed orphan may briefly remain a zombie until launchd reaps it.
        let result = try await ToolRunner.run("/bin/ps", ["-o", "stat=", "-p", String(pid)])
        XCTAssertTrue(
            result.status != 0 || result.text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"),
            result.text)
    }
    func testExitedParentDoesNotWaitForInheritedPipe() async throws {
        let begin = Date()
        let result = try await ToolRunner.run(
            "/usr/bin/python3",
            ["-c", "import subprocess; subprocess.Popen(['/bin/sleep','2']); print('parent finished',flush=True)"],
            timeout: 4)
        XCTAssertLessThan(Date().timeIntervalSince(begin), 1.5)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.text.contains("parent finished"))
    }
    func testToolDrainsBothStreamsWithoutTruncatingSmallOutput() async throws {
        let result = try await ToolRunner.run(
            "/usr/bin/python3", ["-c", "import sys; sys.stdout.write('a'*200000); sys.stderr.write('b'*200000)"])
        XCTAssertEqual(result.stdout, Data(repeating: 97, count: 200000))
        XCTAssertEqual(result.stderr, Data(repeating: 98, count: 200000))
    }
    func testToolCancellationReturnsCancellationErrorPromptly() async throws {
        let task = Task { try await ToolRunner.run("/bin/sleep", ["15"], timeout: 30) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let begin = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(begin), 1)
    }
    func testToolTimeout() async throws {
        do {
            _ = try await ToolRunner.run("/bin/sleep", ["10"], timeout: 0.03)
            XCTFail()
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    L10n.text("Timed out: {0}. See the logs for details.", "").components(separatedBy: ":")[0]))
        }
    }
}

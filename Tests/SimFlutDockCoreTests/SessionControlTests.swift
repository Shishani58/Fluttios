import AppKit
import Foundation
import XCTest

@testable import SimFlutDockCore

final class SessionControlTests: XCTestCase {
    @MainActor func testActualMCPBridgeControlsTheManagersSessionThroughTheSocket() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = SessionManager(simulators: SimulatorService())
        let control = SessionControl(manager: manager)
        let project = Project(name: "MCP wiring", path: "/tmp")
        let firstDevice = SimulatorDevice(udid: "D1", name: "First", state: "Booted")
        let secondDevice = SimulatorDevice(udid: "D2", name: "Second", state: "Booted")
        let first = manager.session(for: project.id, deviceID: firstDevice.id)
        let second = manager.session(for: project.id, deviceID: secondDevice.id)
        try fixture.start(first, project: project, device: firstDevice)
        try fixture.start(second, project: project, device: secondDevice)
        defer {
            first.stop()
            second.stop()
        }
        try await wait { first.state == .running && second.state == .running }
        first.append("wiring-log")

        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appendingPathComponent(".build/mcp-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("control.sock")
        XCTAssertLessThanOrEqual(socket.path.utf8.count + 1, 104)
        let server = LocalControlServer(socketURL: socket, handler: control.handle)
        try server.start()
        defer { server.stop() }
        let bridge = repository.appendingPathComponent("scripts/fluttios-mcp.py")
        // One round trip across all three boundaries catches mismatched framing,
        // argument names or response envelopes that isolated layer tests cannot.
        let driver = """
            import json, subprocess, sys
            bridge = subprocess.Popen(
                [sys.executable, sys.argv[1], "--socket", sys.argv[2]],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            sequence = 0
            def send(message):
                bridge.stdin.write(json.dumps(message) + "\\n")
                bridge.stdin.flush()
            def rpc(method, params):
                global sequence
                sequence += 1
                send({"jsonrpc":"2.0", "id":sequence, "method":method, "params":params})
                response = json.loads(bridge.stdout.readline())
                assert response.get("jsonrpc") == "2.0", response
                assert response.get("id") == sequence, response
                assert "error" not in response, response
                return response["result"]
            def call(name, arguments):
                result = rpc("tools/call", {"name":name, "arguments":arguments})
                assert result.get("isError") is False, result
                assert json.loads(result["content"][0]["text"]) == result["structuredContent"], result
                return result["structuredContent"]
            try:
                initialized = rpc("initialize", {
                    "protocolVersion":"2025-11-25", "capabilities":{},
                    "clientInfo":{"name":"integration-test", "version":"1"}})
                assert initialized["protocolVersion"] == "2025-11-25", initialized
                send({"jsonrpc":"2.0", "method":"notifications/initialized"})
                tools = rpc("tools/list", {})["tools"]
                assert {tool["name"] for tool in tools} == {
                    "list_sessions", "get_session", "read_logs", "hot_reload", "hot_restart", "stop_session",
                    "list_projects", "list_devices", "start_session", "rerun_session", "open_deep_link", "take_screenshot"}, tools
                session_id, launch_id = sys.argv[3:5]
                listed = call("list_sessions", {})["sessions"]
                assert len(listed) == 2, listed
                assert session_id in {session["session_id"] for session in listed}, listed
                snapshot = call("get_session", {"session_id":session_id})["session"]
                assert snapshot["launch_id"] == launch_id and snapshot["state"] == "running", snapshot
                logs = call("read_logs", {"session_id":session_id, "limit":10})
                assert "wiring-log" in [entry["text"] for entry in logs["entries"]], logs
                for action in ("hot_reload", "hot_restart", "stop_session"):
                    result = call(action, {
                        "session_id":session_id, "launch_id":launch_id, "request_id":"wiring-"+action})
                    assert result["status"] == "completed", result
                    assert result["request_id"] == "wiring-"+action, result
                    assert result["session"]["session_id"] == session_id, result
                assert result["session"]["is_alive"] is False, result
            finally:
                bridge.stdin.close()
                try:
                    bridge.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    bridge.kill()
                    bridge.wait()
                errors = bridge.stderr.read()
                assert bridge.returncode == 0, errors
            print("ok")
            """
        let result = try await ToolRunner.run(
            "/usr/bin/python3",
            ["-c", driver, bridge.path, socket.path, first.id.uuidString, first.launchID.uuidString],
            timeout: 20)
        XCTAssertEqual(result.status, 0, result.text)
        XCTAssertEqual(
            String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), "ok")
        XCTAssertFalse(first.isAlive)
        XCTAssertEqual(first.state, .ready)
        XCTAssertTrue(second.isAlive)
        XCTAssertFalse(second.logs.contains { $0.text.hasPrefix("command:") })
        await manager.waitForStop()
    }

    @MainActor func testCommandsTargetOneDeviceAndOldStopCannotStopANewLaunch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = SessionManager(simulators: SimulatorService())
        let control = SessionControl(manager: manager)
        let project = Project(name: "Shared project", path: "/tmp")
        let firstDevice = SimulatorDevice(udid: "D1", name: "First", state: "Booted")
        let secondDevice = SimulatorDevice(udid: "D2", name: "Second", state: "Booted")
        let first = manager.session(for: project.id, deviceID: firstDevice.id)
        let second = manager.session(for: project.id, deviceID: secondDevice.id)
        // A panel lookup alone must not advertise an unlaunched session to the model.
        _ = manager.session(for: UUID(), deviceID: "unused")
        try fixture.start(first, project: project, device: firstDevice)
        try fixture.start(second, project: project, device: secondDevice)
        defer {
            first.stop()
            second.stop()
        }
        try await wait { first.state == .running && second.state == .running }

        let listed = try await invoke(control, "list_sessions")
        let sessions = try XCTUnwrap(listed["sessions"] as? [[String: Any]])
        XCTAssertEqual(
            Set(sessions.compactMap { $0["session_id"] as? String }), [first.id.uuidString, second.id.uuidString])
        XCTAssertEqual(Set(sessions.compactMap { ($0["device"] as? [String: Any])?["id"] as? String }), ["D1", "D2"])

        let reload = try await invoke(control, "hot_reload", command(first, requestID: "reload-first"))
        XCTAssertEqual(reload["status"] as? String, "completed")
        let reloaded = try XCTUnwrap(reload["session"] as? [String: Any])
        XCTAssertEqual(
            reloaded["available_actions"] as? [String],
            ["hot_reload", "hot_restart", "stop_session", "rerun_session", "open_deep_link", "take_screenshot"])
        XCTAssertEqual(first.logs.filter { $0.text == "command:app.restart:false" }.count, 1)
        XCTAssertFalse(second.logs.contains { $0.text.hasPrefix("command:") })

        let restart = try await invoke(control, "hot_restart", command(second, requestID: "restart-second"))
        XCTAssertEqual(restart["status"] as? String, "completed")
        XCTAssertTrue(second.logs.contains { $0.text == "command:app.restart:true" })
        let oldLaunch = first.launchID
        let stopped = try await invoke(control, "stop_session", command(first, requestID: "stop-first"))
        XCTAssertEqual(stopped["status"] as? String, "completed")
        XCTAssertFalse(first.isAlive)
        XCTAssertTrue(second.isAlive)
        let history = try await invoke(control, "get_session", ["session_id": first.id.uuidString])
        XCTAssertEqual((history["session"] as? [String: Any])?["state"] as? String, "ready")

        try fixture.start(first, project: project, device: firstDevice)
        try await wait { first.state == .running }
        XCTAssertNotEqual(first.launchID, oldLaunch)
        let stale = try await invoke(
            control, "stop_session",
            [
                "session_id": first.id.uuidString, "launch_id": oldLaunch.uuidString, "request_id": "late-stop",
            ], error: "STALE_LAUNCH")
        XCTAssertEqual((stale["session"] as? [String: Any])?["launch_id"] as? String, first.launchID.uuidString)
        XCTAssertTrue(first.isAlive)
        XCTAssertEqual(first.state, .running)
        await manager.waitForStop()
    }

    @MainActor func testRetriesJoinTheInflightCommandAndCannotChangeItsMeaning() async throws {
        let fixture = try Fixture(holdRestart: true)
        defer { fixture.remove() }
        let manager = SessionManager(simulators: SimulatorService())
        let control = SessionControl(manager: manager)
        let project = Project(name: "Retry", path: "/tmp")
        let device = SimulatorDevice(udid: "D", name: "Test", state: "Booted")
        let session = manager.session(for: project.id, deviceID: device.id)
        try fixture.start(session, project: project, device: device)
        defer { session.stop() }
        try await wait { session.state == .running }
        let arguments = command(session, requestID: "same-request")
        let first = Task { @MainActor in try await self.invoke(control, "hot_reload", arguments) }
        try await wait { session.logs.contains { $0.text == "command:app.restart:false" } }
        let duplicate = Task { @MainActor in try await self.invoke(control, "hot_reload", arguments) }
        // MainActor yields allow the duplicate to enter while the fixture holds Flutter's response.
        await Task.yield()
        _ = try await invoke(control, "hot_restart", arguments, error: "REQUEST_ID_CONFLICT")
        _ = try await invoke(control, "stop_session", command(session, requestID: "competing-stop"), error: "BUSY")
        XCTAssertEqual(session.state, .reloading)
        try fixture.releaseRestart()
        let firstResult = try await first.value
        let duplicateResult = try await duplicate.value
        XCTAssertTrue(NSDictionary(dictionary: firstResult).isEqual(to: duplicateResult))
        let retried = try await invoke(control, "hot_reload", arguments)
        XCTAssertTrue(NSDictionary(dictionary: firstResult).isEqual(to: retried))
        XCTAssertEqual(session.logs.filter { $0.text == "command:app.restart:false" }.count, 1)
        await manager.waitForStop()
    }

    @MainActor func testFlutterRejectingRestartProducesAnErrorInsteadOfCompleted() async throws {
        let fixture = try Fixture(restartCode: 1)
        defer { fixture.remove() }
        let manager = SessionManager(simulators: SimulatorService())
        let control = SessionControl(manager: manager)
        let project = Project(name: "Compile failure", path: "/tmp")
        let device = SimulatorDevice(udid: "D", name: "Test", state: "Booted")
        let session = manager.session(for: project.id, deviceID: device.id)
        try fixture.start(session, project: project, device: device)
        defer { session.stop() }
        try await wait { session.state == .running }
        let result = try await invoke(
            control, "hot_reload", command(session, requestID: "bad-reload"), error: "COMMAND_FAILED")
        XCTAssertNil(result["status"])
        XCTAssertEqual((result["error"] as? [String: Any])?["message"] as? String, "Compilation failed")
        XCTAssertEqual(session.state, .running)
        XCTAssertTrue(session.isAlive)
        await manager.waitForStop()
    }

    @MainActor func testInvalidUnknownBusyAndReleaseRequestsCannotCreateOrMutateSessions() async throws {
        let manager = SessionManager(simulators: SimulatorService())
        let control = SessionControl(manager: manager)
        _ = try await invoke(control, "get_session", ["session_id": UUID().uuidString], error: "SESSION_NOT_FOUND")
        _ = try await invoke(control, "hot_reload", ["session_id": "not-a-uuid"], error: "INVALID_ARGUMENTS")
        XCTAssertTrue(manager.sessions.isEmpty)

        let project = Project(name: "Preparing", path: "/tmp")
        let device = SimulatorDevice(udid: "D", name: "Test", state: "Available", isPhysical: true)
        let session = manager.session(for: project.id, deviceID: device.id)
        session.prepare(project: project, device: device)
        _ = try await invoke(control, "hot_reload", command(session, requestID: "during-prepare"), error: "BUSY")
        for invalidRequestID in ["", "  ", String(repeating: "x", count: 129)] {
            _ = try await invoke(
                control, "stop_session", command(session, requestID: invalidRequestID), error: "INVALID_ARGUMENTS")
        }
        XCTAssertTrue(session.preparing)
        session.launchFailed(CancellationError())

        let fixture = try Fixture()
        defer { fixture.remove() }
        var releaseProject = project
        releaseProject.launch.setMode(.release)
        try fixture.start(session, project: releaseProject, device: device)
        defer { session.stop() }
        try await wait { session.state == .running }
        let details = try await invoke(control, "get_session", ["session_id": session.id.uuidString])
        let snapshot = try XCTUnwrap(details["session"] as? [String: Any])
        XCTAssertEqual(snapshot["available_actions"] as? [String], ["stop_session", "rerun_session"])
        _ = try await invoke(
            control, "hot_restart", command(session, requestID: "release-restart"), error: "ACTION_UNAVAILABLE")
        XCTAssertFalse(session.logs.contains { $0.text.hasPrefix("command:") })
        XCTAssertEqual(manager.sessions.count, 1)
        await manager.waitForStop()
    }

    @MainActor func testLogCursorsPaginateAndExpireAfterClearOrEvictionWithBoundedResponses() async throws {
        let manager = SessionManager(simulators: SimulatorService())
        let control = SessionControl(manager: manager)
        let project = Project(name: "Logs", path: "/tmp")
        let session = manager.session(for: project.id, deviceID: "D")
        session.prepare(project: project, device: SimulatorDevice(udid: "D", name: "Test", state: "Booted"))
        session.launchFailed(CancellationError())
        session.append("first")
        session.append("second", error: true)
        session.append("third")
        let args: [String: Any] = ["session_id": session.id.uuidString, "limit": 2]
        let page = try await invoke(control, "read_logs", args)
        let entries = try XCTUnwrap(page["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.compactMap { $0["text"] as? String }, ["first", "second"])
        XCTAssertEqual(entries.compactMap { $0["is_error"] as? Bool }, [false, true])
        XCTAssertEqual(page["has_more"] as? Bool, true)
        let cursor = try XCTUnwrap(page["next_cursor"] as? String)
        let next = try await invoke(control, "read_logs", ["session_id": session.id.uuidString, "cursor": cursor])
        XCTAssertEqual((next["entries"] as? [[String: Any]])?.compactMap { $0["text"] as? String }, ["third"])
        XCTAssertEqual(next["has_more"] as? Bool, false)
        let tailCursor = try XCTUnwrap(next["next_cursor"] as? String)
        let empty = try await invoke(control, "read_logs", ["session_id": session.id.uuidString, "cursor": tailCursor])
        XCTAssertEqual((empty["entries"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(empty["next_cursor"] as? String, tailCursor)

        for limit in [0, 201, true, 1.5, "2"] as [Any] {
            _ = try await invoke(
                control, "read_logs", ["session_id": session.id.uuidString, "limit": limit], error: "INVALID_ARGUMENTS")
        }
        session.clearLogs()
        session.append("after clear")
        _ = try await invoke(
            control, "read_logs", ["session_id": session.id.uuidString, "cursor": cursor], error: "CURSOR_EXPIRED")
        let beforeEviction = try await invoke(control, "read_logs", ["session_id": session.id.uuidString])
        let evictedCursor = try XCTUnwrap(beforeEviction["next_cursor"] as? String)
        for index in 0..<2_001 { session.append("entry \(index)") }
        _ = try await invoke(
            control, "read_logs", ["session_id": session.id.uuidString, "cursor": evictedCursor],
            error: "CURSOR_EXPIRED")
        let boundedRows = try await invoke(control, "read_logs", ["session_id": session.id.uuidString, "limit": 200])
        XCTAssertEqual((boundedRows["entries"] as? [[String: Any]])?.count, 200)
        XCTAssertEqual(boundedRows["has_more"] as? Bool, true)

        session.clearLogs()
        for _ in 0..<5 { session.append(String(repeating: "x", count: 16_384)) }
        let boundedBytes = try await invoke(control, "read_logs", ["session_id": session.id.uuidString, "limit": 200])
        XCTAssertEqual((boundedBytes["entries"] as? [[String: Any]])?.count, 4)
        XCTAssertEqual(boundedBytes["has_more"] as? Bool, true)
    }

    @MainActor func testSavedProjectsRequireAnExplicitFreshDeviceWithoutChangingPanelSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "name: test_project\ndependencies:\n  flutter:\n    sdk: flutter\n".write(
            to: directory.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        let store = ProjectStore(file: directory.appendingPathComponent("projects.json"))
        var project = try store.open(directory)
        project.launch.entrypoint = "lib/staging.dart"
        project.launch.setMode(.profile)
        store.update(project)
        let manager = SessionManager(
            simulators: SimulatorService(cacheFile: directory.appendingPathComponent("devices.json")))
        let control = SessionControl(manager: manager, store: store)
        let listed = try await invoke(control, "list_projects")
        let row = try XCTUnwrap((listed["projects"] as? [[String: Any]])?.first)
        let config = try XCTUnwrap(row["configuration"] as? [String: Any])
        XCTAssertEqual(row["id"] as? String, project.id.uuidString)
        XCTAssertEqual(config["entrypoint"] as? String, "lib/staging.dart")
        XCTAssertEqual(config["mode"] as? String, "profile")
        _ = try await invoke(
            control, "start_session",
            ["project_id": project.id.uuidString, "device_id": "unknown", "request_id": "start"],
            error: "DEVICE_UNAVAILABLE")
        _ = try await invoke(
            control, "start_session",
            ["project_id": UUID().uuidString, "device_id": "unknown", "request_id": "missing"],
            error: "PROJECT_NOT_FOUND")
        XCTAssertTrue(manager.sessions.isEmpty)
        XCTAssertEqual(store.selectedID, project.id)
    }

    @MainActor func testRerunStopsOnlyTheExplicitLaunchAndRetriesDoNotRerunAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = SessionManager(simulators: SimulatorService())
        let control = SessionControl(manager: manager)
        let project = Project(name: "Rerun", path: "/nonexistent-fluttios-rerun-test")
        let device = SimulatorDevice(udid: "D1", name: "First", state: "Booted")
        let other = SimulatorDevice(udid: "D2", name: "Second", state: "Booted")
        let first = manager.session(for: project.id, deviceID: device.id)
        let second = manager.session(for: project.id, deviceID: other.id)
        // Fixture controls only Flutter process I/O, while real SessionManager owns the rerun.
        var fixtureProject = project
        fixtureProject.path = "/tmp"
        try fixture.start(first, project: fixtureProject, device: device)
        try fixture.start(second, project: fixtureProject, device: other)
        defer {
            first.stop()
            second.stop()
        }
        try await wait { first.state == .running && second.state == .running }
        let original = first.launchID
        let args = command(first, requestID: "one-rerun")
        let result = try await invoke(control, "rerun_session", args)
        XCTAssertEqual(result["status"] as? String, "started")
        XCTAssertNotEqual(first.launchID, original)
        let newLaunch = first.launchID
        let retry = try await invoke(control, "rerun_session", args)
        XCTAssertTrue(NSDictionary(dictionary: result).isEqual(to: retry))
        XCTAssertEqual(first.launchID, newLaunch)
        XCTAssertTrue(second.isAlive)
        _ = try await invoke(
            control, "take_screenshot", commandWithLaunch(first, launch: original, requestID: "stale-capture"),
            error: "STALE_LAUNCH")
        _ = try await invoke(
            control, "rerun_session", args.merging(["request_id": "new-old-launch"]) { _, new in new },
            error: "STALE_LAUNCH")
        await manager.waitForStop()
    }

    @MainActor func testScreenshotReturnsBoundedNativeImageForExactAndroidDeviceAndRetriesReuseCapture() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let tools = directory.appendingPathComponent("platform-tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2400, pixelsHigh: 1200,
                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        memset(source.bitmapData!, 255, source.bytesPerRow * source.pixelsHigh)
        let png = try XCTUnwrap(source.representation(using: .png, properties: [:]))
        let input = directory.appendingPathComponent("screen.png")
        try png.write(to: input)
        let invocations = directory.appendingPathComponent("captures.txt")
        let adb = tools.appendingPathComponent("adb")
        // Real process boundary: the stand-in emits only a PNG and records invocation arguments.
        try "#!/bin/sh\nprintf '%s\\n' \"$*\" >> '\(invocations.path)'\n/bin/cat '\(input.path)'\n".write(
            to: adb, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: adb.path)
        let previous = ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"]
        setenv("ANDROID_SDK_ROOT", directory.path, 1)
        defer { if let previous { setenv("ANDROID_SDK_ROOT", previous, 1) } else { unsetenv("ANDROID_SDK_ROOT") } }
        let manager = SessionManager(simulators: SimulatorService())
        let control = SessionControl(manager: manager)
        let project = Project(name: "Screenshot", path: "/tmp")
        let device = SimulatorDevice(
            udid: "emulator-5554", name: "Android", state: "Booted", targetPlatform: "android-arm64")
        let session = manager.session(for: project.id, deviceID: device.id)
        try fixture.start(session, project: project, device: device)
        defer { session.stop() }
        try await wait { session.state == .running }
        let args = command(session, requestID: "capture")
        let request = try JSONSerialization.data(withJSONObject: ["tool": "take_screenshot", "arguments": args])
        let responseData = await control.handle(request)
        let response = try XCTUnwrap(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        XCTAssertEqual(response["isError"] as? Bool, false)
        let image = try XCTUnwrap((response["content"] as? [[String: Any]])?.last)
        XCTAssertEqual(image["type"] as? String, "image")
        XCTAssertEqual(image["mimeType"] as? String, "image/jpeg")
        let data = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(image["data"] as? String)))
        XCTAssertLessThanOrEqual(data.count, 1_000_000)
        let jpeg = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(jpeg.pixelsWide, 1600)
        XCTAssertEqual(jpeg.pixelsHigh, 800)
        // A valid image envelope must contain the captured pixels, not an empty canvas.
        let color = try XCTUnwrap(jpeg.colorAt(x: 800, y: 400)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.95)
        XCTAssertGreaterThan(color.greenComponent, 0.95)
        XCTAssertGreaterThan(color.blueComponent, 0.95)
        let structured = try XCTUnwrap(response["structuredContent"] as? [String: Any])
        let path = try XCTUnwrap(structured["image_path"] as? String)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), data)
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        _ = try await invoke(control, "take_screenshot", args)
        XCTAssertEqual(try String(contentsOf: invocations), "-s emulator-5554 exec-out screencap -p\n")
        await manager.waitForStop()
    }

    @MainActor func testAndroidLinkURLRemainsOneLiteralShellArgument() async throws {
        let url = "myapp://path?a=1&b='quote';x=$(uname)"
        let args = try AndroidDeviceCommand.deepLinkArguments(deviceID: "emulator-5554", url: url)
        XCTAssertEqual(Array(args.prefix(3)), ["-s", "emulator-5554", "shell"])
        // Run a real shell, the same parsing boundary adb uses, without opening any URL.
        let result = try await ToolRunner.run("/bin/sh", ["-c", "printf '%s' " + args.last!]).checked()
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "myapp://path?a=1&b='quote';x=$(uname)")
    }

    @MainActor private func commandWithLaunch(_ session: FlutterSession, launch: UUID, requestID: String) -> [String:
        Any]
    {
        ["session_id": session.id.uuidString, "launch_id": launch.uuidString, "request_id": requestID]
    }

    @MainActor private func command(_ session: FlutterSession, requestID: String) -> [String: Any] {
        ["session_id": session.id.uuidString, "launch_id": session.launchID.uuidString, "request_id": requestID]
    }

    @MainActor private func invoke(
        _ control: SessionControl, _ tool: String, _ arguments: [String: Any] = [:], error expectedError: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws -> [String: Any] {
        let request = try JSONSerialization.data(withJSONObject: ["tool": tool, "arguments": arguments])
        let response = await control.handle(request)
        let envelope = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: response) as? [String: Any], file: file, line: line)
        XCTAssertEqual(envelope["isError"] as? Bool, expectedError != nil, file: file, line: line)
        let result = try XCTUnwrap(envelope["structuredContent"] as? [String: Any], file: file, line: line)
        XCTAssertEqual((result["error"] as? [String: Any])?["code"] as? String, expectedError, file: file, line: line)
        let content = try XCTUnwrap(envelope["content"] as? [[String: Any]], file: file, line: line)
        let text = try XCTUnwrap(content.first?["text"] as? String, file: file, line: line)
        let textResult = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: textResult).isEqual(to: result), file: file, line: line)
        return result
    }

    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { throw SimFlutDockError.timeout("Session control test") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // Uses the real process/parser/client; the gate controls only when Flutter replies.
    private struct Fixture {
        let directory: URL
        let script: URL
        let gate: URL

        init(holdRestart: Bool = false, restartCode: Int = 0) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            script = directory.appendingPathComponent("flutter.py")
            gate = directory.appendingPathComponent("release")
            try """
            #!/usr/bin/python3
            import json, os, sys, time
            def send(message): print(json.dumps([message]), flush=True)
            send({"event":"app.start","params":{"appId":"app"}})
            send({"event":"app.started","params":{"appId":"app"}})
            for line in sys.stdin:
                command = json.loads(line)[0]
                method = command["method"]
                full = str(command.get("params", {}).get("fullRestart", False)).lower()
                send({"event":"app.log","params":{"appId":"app","log":"command:"+method+":"+full}})
                if method == "app.restart":
                    if \(holdRestart ? "True" : "False"):
                        deadline = time.monotonic() + 10
                        while not os.path.exists(os.path.join(os.path.dirname(__file__), "release")):
                            if time.monotonic() >= deadline: raise RuntimeError("Restart gate was not released")
                            time.sleep(0.01)
                    send({"id":command["id"],"result":{"code":\(restartCode),"message":"Compilation failed"}})
                else:
                    send({"id":command["id"],"result":{"code":0}})
                if method == "app.stop":
                    send({"event":"app.stop","params":{"appId":"app"}})
                    break
            """.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        }

        @MainActor func start(_ session: FlutterSession, project: Project, device: SimulatorDevice) throws {
            try session.start(
                executable: script.path, project: project, device: device, bundleID: "com.test.control",
                captureDartConsole: false)
        }

        func releaseRestart() throws { try Data().write(to: gate) }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}

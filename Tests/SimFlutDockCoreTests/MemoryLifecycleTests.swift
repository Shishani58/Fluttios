import Darwin
import XCTest

@testable import SimFlutDockCore

final class MemoryLifecycleTests: XCTestCase {
    @MainActor func testLogBudgetKeepsNewestEntriesAndResetsAfterClear() {
        let session = FlutterSession(projectID: UUID())
        for n in 0..<2000 { session.append("\(n):" + String(repeating: "я", count: 8000)) }
        XCTAssertLessThanOrEqual(session.logs.reduce(0) { $0 + $1.text.utf8.count }, FlutterSession.logByteLimit)
        XCTAssertTrue(session.logs.last?.text.hasPrefix("1999:") == true)
        XCTAssertLessThan(session.logs.count, 2000)
        session.clearLogs()
        for n in 0..<2000 { session.append("line \(n)") }
        XCTAssertEqual(session.logs.count, 2000)
        XCTAssertEqual(session.logs.first?.text, "line 0")
    }

    @MainActor func testSingleGraphemeCannotBypassLogByteBudget() throws {
        let session = FlutterSession(projectID: UUID())
        session.append("a" + String(repeating: "\u{301}", count: 100_000))
        XCTAssertLessThanOrEqual(try XCTUnwrap(session.logs.first).text.utf8.count, 16_386)
    }

    @MainActor func testRemovingInactiveSessionReleasesItsLogsAndObservation() {
        let manager = SessionManager(simulators: SimulatorService())
        let id = SessionKey(projectID: UUID(), deviceID: "D")
        weak var released: FlutterSession?
        do {
            let session = manager.session(for: id.projectID, deviceID: id.deviceID)
            released = session
            session.append(String(repeating: "x", count: 16_384))
        }
        manager.removeInactiveSession(id)
        XCTAssertNil(manager.sessions[id])
        XCTAssertNil(released)
        let activeKey = SessionKey(projectID: UUID(), deviceID: "D")
        let active = manager.session(for: activeKey.projectID, deviceID: activeKey.deviceID)
        active.prepare(
            project: Project(name: "Active", path: "/tmp"),
            device: SimulatorDevice(udid: "D", name: "Test", state: "Booted"))
        manager.removeInactiveSession(activeKey)
        XCTAssertTrue(manager.sessions[activeKey] === active)
        active.launchFailed(CancellationError())
    }

    @MainActor func testExitAndStopKillOwnedDescendantAndPreserveOtherSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let device = SimulatorDevice(udid: "D", name: "Test", state: "Booted")
        let other = FlutterSession(projectID: UUID())
        let otherScript = directory.appendingPathComponent("other.py")
        try executable("#!/usr/bin/python3\nimport time\ntime.sleep(60)\n", at: otherScript)
        try other.start(
            executable: otherScript.path, project: Project(name: "Other", path: "/tmp"),
            device: device, bundleID: "com.test.other", captureDartConsole: false)
        defer { other.stop() }

        for intentional in [false, true] {
            let pidFile = directory.appendingPathComponent("child-\(intentional).pid")
            let script = directory.appendingPathComponent("parent.py")
            let child =
                "import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); open('\(pidFile.path)','w').write(str(os.getpid())); time.sleep(60)"
            let encoded = Data(child.utf8).base64EncodedString()
            try executable(
                """
                #!/usr/bin/python3
                import subprocess, sys, json, os, time
                subprocess.Popen(['/usr/bin/python3','-c',"import base64; exec(base64.b64decode('\(encoded)'))"])
                while not os.path.exists('\(pidFile.path)'): time.sleep(0.01)
                print('[{"event":"app.start","params":{"appId":"app"}},{"event":"app.started"}]', flush=True)
                if \(intentional ? "True" : "False"):
                    command = json.loads(sys.stdin.readline())[0]
                    print(json.dumps([{'id':command['id'],'result':{}},{'event':'app.stop','params':{'appId':'app'}}]), flush=True)
                else:
                    time.sleep(0.2)
                """, at: script)
            let session = FlutterSession(projectID: UUID())
            try session.start(
                executable: script.path, project: Project(name: "Parent", path: "/tmp"),
                device: device, bundleID: "com.test.parent", captureDartConsole: false)
            defer { session.stop() }
            try await wait { session.state == .running }
            let childPID = try XCTUnwrap(Int32(String(contentsOf: pidFile)))
            defer { kill(childPID, SIGKILL) }
            XCTAssertEqual(kill(childPID, 0), 0)
            if intentional { session.stop() }
            try await wait { !session.isAlive }
            try await wait { kill(childPID, 0) == -1 && errno == ESRCH }
            XCTAssertTrue(other.isAlive)
            XCTAssertEqual(session.state, intentional ? .ready : .disconnected)
        }
        other.stop()
        try await wait { !other.isAlive }
    }

    private func executable(_ source: String, at url: URL) throws {
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !condition() {
            guard Date() < deadline else { throw SimFlutDockError.timeout("memory lifecycle test") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

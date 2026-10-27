import XCTest

@testable import SimFlutDockCore

final class DartConsoleStartupTests: XCTestCase {
    @MainActor func testResumesWorkersCreatedAfterInitialSnapshotAndAfterRestart() async throws {
        var console: DartConsole!
        var states = ["main": "PauseStart"]
        var resumed: [String] = []
        let workerResumed = expectation(description: "Late worker resumed")
        let restartedWorkerResumed = expectation(description: "Worker after restart resumed")
        let rpc = MachineClient(arrayWrapped: false) { data in
            let request = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let params = request["params"] as! [String: Any]
            let id = params["isolateId"] as? String ?? ""
            let result: [String: Any]
            switch request["method"] as? String {
            case "getVM":
                result = ["isolates": [["id": "main", "name": "main"]]]
            case "getIsolate":
                result = ["pauseEvent": ["kind": states[id] ?? "Resume"]]
            case "resume":
                resumed.append(id)
                states[id] = "Resume"
                result = ["type": "Success"]
                if id == "worker" { workerResumed.fulfill() }
                if id == "restarted-worker" { restartedWorkerResumed.fulfill() }
            default:
                XCTFail("Unexpected RPC")
                result = [:]
            }
            console.receive(["id": request["id"]!, "result": result])
        }
        console = DartConsole(rpc: rpc)
        defer { console.close() }
        try await console.resumePausedIsolates()
        XCTAssertEqual(resumed, ["main"])

        states["worker"] = "PauseStart"
        console.receive(event("PauseStart", isolate: "worker"))
        console.receive(event("PauseStart", isolate: "worker"))
        await fulfillment(of: [workerResumed], timeout: 2)

        states["restarted-worker"] = "PauseStart"
        console.receive(event("PauseStart", isolate: "restarted-worker"))
        await fulfillment(of: [restartedWorkerResumed], timeout: 2)
        XCTAssertEqual(resumed, ["main", "worker", "restarted-worker"])
    }

    @MainActor func testPreservesBreakpointPausesAndIgnoresStaleEventsAndClosedConsole() async throws {
        var console: DartConsole!
        var methods: [String] = []
        let rpc = MachineClient(arrayWrapped: false) { data in
            let request = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let method = request["method"] as! String
            methods.append(method)
            let result: [String: Any] =
                method == "getVM"
                ? ["isolates": [["id": "main"]]]
                : ["pauseEvent": ["kind": "PauseBreakpoint"]]
            console.receive(["id": request["id"]!, "result": result])
        }
        console = DartConsole(rpc: rpc)
        try await console.resumePausedIsolates()
        XCTAssertEqual(methods, ["getVM", "getIsolate"])
        console.receive(event("PauseBreakpoint", isolate: "main"))
        console.receive(event("PauseStart", isolate: "main"))
        // A stale startup event must recheck the current breakpoint state.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(methods, ["getVM", "getIsolate", "getIsolate"])
        console.close()
        console.receive(event("PauseStart", isolate: "closed-worker"))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(methods.contains("resume"))
        XCTAssertEqual(methods.count, 3)
    }

    @MainActor func testStartupTimeoutKeepsConsoleUsableAndRetriesWithFreshPauseState() async throws {
        for timedOutMethod in ["getIsolate", "resume"] {
            var console: DartConsole!
            var timeouts = 0
            var resumes = 0
            var disconnected = false
            let handled = expectation(description: "Startup timeout handled: \(timedOutMethod)")
            var output = ""
            let rpc = MachineClient(arrayWrapped: false) { data in
                let request = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let method = request["method"] as! String
                if method == timedOutMethod, timeouts == 0 {
                    timeouts += 1
                    throw SimFlutDockError.timeout(method)
                }
                // A timed-out resume may have succeeded; never resume a later breakpoint.
                let state = timedOutMethod == "resume" && timeouts > 0 ? "PauseBreakpoint" : "PauseStart"
                if method == "resume" { resumes += 1 }
                let result: [String: Any] =
                    method == "getIsolate"
                    ? ["pauseEvent": ["kind": state]] : ["type": "Success"]
                console.receive(["id": request["id"]!, "result": result])
                if timeouts > 0, method == "resume" || state == "PauseBreakpoint" { handled.fulfill() }
            }
            console = DartConsole(rpc: rpc)
            defer { console.close() }
            console.onDisconnect = { _ in
                disconnected = true
                handled.fulfill()
            }
            console.onOutput = { data, _ in output += String(decoding: data, as: UTF8.self) }
            console.receive(event("PauseStart", isolate: "worker"))
            await fulfillment(of: [handled], timeout: 2)
            console.receive([
                "method": "streamNotify",
                "params": [
                    "streamId": "Stdout",
                    "event": [
                        "kind": "WriteEvent",
                        "bytes": Data("still connected".utf8).base64EncodedString(),
                    ],
                ],
            ])
            XCTAssertFalse(disconnected)
            XCTAssertTrue(output.contains("still connected"))
            XCTAssertEqual(resumes, timedOutMethod == "getIsolate" ? 1 : 0)
        }
    }

    @MainActor func testRepeatedStartupTimeoutIsBoundedAndLeavesOtherIsolatesUsable() async throws {
        var console: DartConsole!
        var attempts = 0
        var disconnected = false
        let warned = expectation(description: "Timeout logged without disconnect")
        let healthyResumed = expectation(description: "Other isolate resumed")
        let rpc = MachineClient(arrayWrapped: false) { data in
            let request = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let params = request["params"] as! [String: Any]
            let method = request["method"] as! String
            if params["isolateId"] as? String == "stalled" {
                attempts += 1
                throw SimFlutDockError.timeout(method)
            }
            let result: [String: Any] =
                method == "getIsolate"
                ? ["pauseEvent": ["kind": "PauseStart"]] : ["type": "Success"]
            console.receive(["id": request["id"]!, "result": result])
            if method == "resume" { healthyResumed.fulfill() }
        }
        console = DartConsole(rpc: rpc)
        defer { console.close() }
        console.onDisconnect = { _ in
            disconnected = true
            warned.fulfill()
        }
        console.onOutput = { _, isError in if isError { warned.fulfill() } }
        console.receive(event("PauseStart", isolate: "stalled"))
        await fulfillment(of: [warned], timeout: 2)
        console.receive(event("PauseStart", isolate: "healthy"))
        await fulfillment(of: [healthyResumed], timeout: 2)
        XCTAssertFalse(disconnected)
        XCTAssertEqual(attempts, 2)
    }

    @MainActor func testSnapshotTimeoutAllowsLaterRecoveryOnSameConnection() async throws {
        var console: DartConsole!
        var stalled = true
        var warnings = 0
        var resumed = false
        let rpc = MachineClient(arrayWrapped: false) { data in
            let request = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let method = request["method"] as! String
            if stalled { throw SimFlutDockError.timeout(method) }
            let result: [String: Any]
            switch method {
            case "getVM": result = ["isolates": [["id": "main"]]]
            case "getIsolate": result = ["pauseEvent": ["kind": "PauseStart"]]
            default:
                resumed = true
                result = ["type": "Success"]
            }
            console.receive(["id": request["id"]!, "result": result])
        }
        console = DartConsole(rpc: rpc)
        defer { console.close() }
        console.onOutput = { _, isError in if isError { warnings += 1 } }
        try await console.resumePausedIsolates()
        XCTAssertEqual(warnings, 1)
        stalled = false
        try await console.resumePausedIsolates()
        XCTAssertTrue(resumed)
    }

    private func event(_ kind: String, isolate: String) -> [String: Any] {
        [
            "method": "streamNotify",
            "params": [
                "streamId": "Debug",
                "event": ["kind": kind, "isolate": ["id": isolate, "isSystemIsolate": false]],
            ],
        ]
    }
}

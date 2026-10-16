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

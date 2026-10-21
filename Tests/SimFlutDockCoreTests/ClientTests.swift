import XCTest

@testable import SimFlutDockCore

final class ClientTests: XCTestCase {
    @MainActor func testResponseRoutingErrorsAndUniqueIDs() async throws {
        var writes: [[String: Any]] = []
        let client = MachineClient { data in writes += try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        }
        let a = Task { try await client.request("app.restart", params: [:]) }
        let b = Task { try await client.request("app.stop", params: [:]) }
        while writes.count < 2 { await Task.yield() }
        let first = writes[0]["id"] as! Int
        let second = writes[1]["id"] as! Int
        XCTAssertNotEqual(first, second)
        client.receive(["id": second, "error": "failure"])
        client.receive(["id": first, "result": true])
        let response = try await a.value
        XCTAssertEqual(response["result"] as? Bool, true)
        do {
            _ = try await b.value
            XCTFail()
        } catch { XCTAssertTrue(error.localizedDescription.contains("failure")) }
        XCTAssertEqual(client.pendingCount, 0)
    }
    @MainActor func testTimeoutTerminationAndCancellationCleanPendingRequests() async throws {
        let client = MachineClient { _ in }
        do {
            _ = try await client.request("timeout", params: [:], timeout: 0.01)
            XCTFail()
        } catch { XCTAssertTrue(error.localizedDescription.contains("timeout")) }
        XCTAssertEqual(client.pendingCount, 0)
        let pending = Task { try await client.request("close", params: [:]) }
        while client.pendingCount == 0 { await Task.yield() }
        client.close()
        do {
            _ = try await pending.value
            XCTFail()
        } catch {}
        XCTAssertEqual(client.pendingCount, 0)
        let cancellationClient = MachineClient { _ in }
        let cancel = Task { try await cancellationClient.request("cancel", params: [:]) }
        while cancellationClient.pendingCount == 0 { await Task.yield() }
        cancel.cancel()
        do {
            _ = try await cancel.value
            XCTFail()
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(cancellationClient.pendingCount, 0)
    }
    @MainActor func testClosedClientRejectsRequestsWithoutWritingOrWaitingForTimeout() async {
        var writes = 0
        let client = MachineClient { _ in writes += 1 }
        client.close(error: SimFlutDockError.message("Connection closed"))
        do {
            _ = try await client.request("getVM", params: [:])
            XCTFail("A closed transport cannot accept new requests")
        } catch { XCTAssertEqual(error.localizedDescription, "Connection closed") }
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(client.pendingCount, 0)
    }
    @MainActor func testVMServiceUsesUnwrappedRequests() async throws {
        var request: [String: Any]?
        let client = MachineClient(arrayWrapped: false) { data in
            request = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let task = Task { try await client.request("getVM", params: [:]) }
        while request == nil { await Task.yield() }
        XCTAssertEqual(request?["method"] as? String, "getVM")
        client.receive(["id": request!["id"]!, "result": ["type": "VM"]])
        let response = try await task.value
        XCTAssertEqual((response["result"] as? [String: Any])?["type"] as? String, "VM")
    }
    @MainActor func testWriteFailure() async {
        let client = MachineClient { _ in throw SimFlutDockError.exited }
        do {
            _ = try await client.request("write", params: [:])
            XCTFail()
        } catch {}
        XCTAssertEqual(client.pendingCount, 0)
    }
}

import XCTest

@testable import SimFlutDockCore

final class DartMemoryTests: XCTestCase {
    func testHeapUsageDoesNotIncludeCapacityOrExternalMemory() {
        XCTAssertEqual(
            DartConsole.heapBytes(from: [
                "result": ["type": "MemoryUsage", "heapUsage": 1024, "heapCapacity": 4096, "externalUsage": 2048]
            ]), 1024)
        XCTAssertEqual(DartConsole.heapBytes(from: ["result": ["type": "MemoryUsage", "heapUsage": 0]]), 0)
    }

    func testMissingCollectedAndInvalidSamplesStayUnavailable() {
        for response: [String: Any] in [
            [:], ["result": ["type": "Sentinel", "kind": "Collected"]],
            ["result": ["type": "MemoryUsage", "heapUsage": -1]],
            ["result": ["type": "MemoryUsage", "heapUsage": true]],
            ["result": ["type": "MemoryUsage", "heapUsage": 1.5]],
        ] {
            XCTAssertNil(DartConsole.heapBytes(from: response))
        }
    }

    @MainActor func testInactiveSessionHasNoMemorySample() async {
        let session = FlutterSession(projectID: UUID())
        let bytes = await session.mainIsolateHeapBytes()
        XCTAssertNil(bytes)
        XCTAssertEqual(session.state, .ready)
    }
}

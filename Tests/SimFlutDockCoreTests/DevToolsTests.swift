import XCTest

@testable import SimFlutDockCore

final class DevToolsTests: XCTestCase {
    @MainActor func testDevToolsFollowsTheCurrentAppAndIsClearedBeforeRerun() async throws {
        let session = FlutterSession(projectID: UUID())
        let project = Project(name: "DevTools", path: "/tmp")
        let device = SimulatorDevice(udid: "TEST", name: "Test", state: "Booted")
        func event(_ name: String, appID: String? = "owned", uri: String? = nil) {
            var params: [String: Any] = [:]
            params["appId"] = appID
            params["uri"] = uri
            session.handle(.message(["event": name, "params": params]))
        }
        let firstURL = "http://127.0.0.1:9100/?uri=http%3A%2F%2F127.0.0.1%3A51830%2Ffirst%3D%2F"
        try session.start(
            executable: "/usr/bin/true", project: project, device: device, bundleID: "com.test.devtools",
            captureDartConsole: false)
        event("app.start")
        event("app.devTools", uri: firstURL)
        XCTAssertFalse(session.canOpenDevTools, "The build has not finished yet")
        event("app.started")
        XCTAssertTrue(session.canOpenDevTools)
        XCTAssertEqual(session.devToolsURL?.absoluteString, firstURL)
        event("app.devTools", appID: "foreign", uri: "http://localhost:9200/")
        event("app.devTools", appID: nil, uri: "http://localhost:9200/")
        XCTAssertEqual(session.devToolsURL?.absoluteString, firstURL)
        session.stop()
        event("app.devTools", uri: firstURL)
        XCTAssertNil(session.devToolsURL)
        XCTAssertFalse(session.canOpenDevTools)
        let deadline = Date().addingTimeInterval(3)
        while session.isAlive && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(session.isAlive)

        try session.start(
            executable: "/usr/bin/true", project: project, device: device, bundleID: "com.test.devtools",
            captureDartConsole: false)
        event("app.start")
        event("app.started")
        XCTAssertNil(session.devToolsURL, "A new launch must wait for its own DevTools address")
        XCTAssertFalse(session.canOpenDevTools)
        event("app.devTools", uri: "http://localhost:9200/")
        XCTAssertEqual(session.devToolsURL?.absoluteString, "http://localhost:9200/")
        XCTAssertTrue(session.canOpenDevTools)
        event("app.stop")
        event("app.devTools", uri: firstURL)
        XCTAssertNil(session.devToolsURL)
        XCTAssertFalse(session.canOpenDevTools)
        while session.isAlive && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(session.isAlive)
    }

    func testDevToolsPreservesConnectionTokenAndRejectsExternalOrExecutableLinks() {
        let address = "http://127.0.0.1:9100/?uri=http%3A%2F%2F127.0.0.1%3A51830%2Ftoken%3D%2F"
        XCTAssertEqual(DevToolsLink.url(from: address)?.absoluteString, address)
        XCTAssertNotNil(
            DevToolsLink.url(from: "http://[::1]:9100/?uri=ws%3A%2F%2F%5B%3A%3A1%5D%3A51830%2Ftoken%3D%2Fws"))
        for address in [
            "https://example.com:9100/", "file:///tmp/devtools.html", "javascript:alert(1)",
            "http://127.0.0.1:9100@evil.example:9100/", "http://localhost:0/",
            "http://localhost:9100/?uri=https%3A%2F%2Fexample.com%3A443%2F",
            "http://localhost:9100/?dtdUri=ws%3A%2F%2Fexample.com%3A1234%2F",
            "http://localhost:9100/?uri=broken",
        ] {
            XCTAssertNil(DevToolsLink.url(from: address), address)
        }
        XCTAssertNil(DevToolsLink.url(from: nil))
    }
}

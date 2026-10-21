import XCTest

@testable import SimFlutDockCore

final class SimulatorToolsTests: XCTestCase {
    private let device = SimulatorDevice(udid: "SIM-A", name: "iPhone", state: "Booted")
    func testCommandsAlwaysTargetExactDeviceAndApplication() throws {
        XCTAssertEqual(
            try SimulatorToolCommand.arguments(device: device, operation: "permissions", value: "com.example.app"),
            ["simctl", "privacy", "SIM-A", "reset", "all", "com.example.app"])
        XCTAssertEqual(
            try SimulatorToolCommand.arguments(device: device, operation: "container", value: "com.example.app"),
            ["simctl", "get_app_container", "SIM-A", "com.example.app", "data"])
        XCTAssertEqual(
            try SimulatorToolCommand.arguments(device: device, operation: "openurl", value: "myapp://profile?id=42"),
            ["simctl", "openurl", "SIM-A", "myapp://profile?id=42"])
        XCTAssertThrowsError(try SimulatorToolCommand.arguments(device: device, operation: "permissions", value: ""))
        XCTAssertThrowsError(
            try SimulatorToolCommand.arguments(device: device, operation: "unknown", value: "com.example.app"))
    }
    func testUnavailableOrAmbiguousTargetsCannotExecuteTools() {
        for target in [
            SimulatorDevice(udid: "SIM-B", name: "Off", state: "Shutdown"),
            SimulatorDevice(udid: "booted", name: "Ambiguous", state: "Booted"),
            SimulatorDevice(udid: "PHONE", name: "Phone", state: "Booted", isPhysical: true),
            SimulatorDevice(udid: "MAC", name: "Mac", state: "Booted", targetPlatform: "darwin", isEmulator: false),
        ] {
            XCTAssertThrowsError(
                try SimulatorToolCommand.arguments(device: target, operation: "permissions", value: "com.example.app"))
        }
    }
    func testLinksRequireUsableSchemeAndPreserveQuery() throws {
        XCTAssertEqual(
            try SavedDeepLink.validatedURL("  myapp://order/42?name=A%20B&mode=test  "),
            "myapp://order/42?name=A%20B&mode=test")
        XCTAssertEqual(try SavedDeepLink.validatedURL("https://example.com/profile"), "https://example.com/profile")
        for invalid in [
            "", "profile/42", "https://", "https://example.com/a b", "file:///tmp/a", "javascript:alert(1)",
            "myapp://a\nb",
        ] {
            XCTAssertThrowsError(try SavedDeepLink.validatedURL(invalid), invalid)
        }
    }
    func testOlderProjectArchivesDecodeWithoutLinks() throws {
        let project = Project(name: "Existing", path: "/tmp/existing")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        json.removeValue(forKey: "deepLinks")
        let restored = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, project)
    }
    @MainActor func testLinksPersistIndependentlyAcrossProjectsAndCanBeRemoved() throws {
        struct Archive: Encodable {
            let projects: [Project]
            let selectedID: UUID
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects.json")
        var first = Project(name: "A", path: "/tmp/a")
        let second = Project(name: "B", path: "/tmp/b")
        try JSONEncoder().encode(Archive(projects: [first, second], selectedID: first.id)).write(to: file)
        let store = ProjectStore(file: file)
        let link = SavedDeepLink(name: "Profile", url: "myapp://profile")
        first.deepLinks = [link]
        store.update(first)
        let restored = ProjectStore(file: file)
        XCTAssertEqual(restored.projects[0].deepLinks, [link])
        XCTAssertTrue(restored.projects[1].deepLinks.isEmpty)
        first.deepLinks[0].name = "My profile"
        store.update(first)
        XCTAssertEqual(ProjectStore(file: file).projects[0].deepLinks[0].name, "My profile")
        first.deepLinks.removeAll()
        store.update(first)
        XCTAssertTrue(ProjectStore(file: file).projects[0].deepLinks.isEmpty)
        XCTAssertNil(store.persistenceError)
    }
}

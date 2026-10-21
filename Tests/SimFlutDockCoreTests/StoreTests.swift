import XCTest

@testable import SimFlutDockCore

final class StoreTests: XCTestCase {
    @MainActor func testClearingSavedProjectsPersistsEmptyListAndPreservesFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let projectFolders = [folder.appendingPathComponent("A"), folder.appendingPathComponent("B")]
        for url in projectFolders {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try "name: counter\ndependencies:\n  flutter:\n    sdk: flutter\n".write(
                to: url.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
            try "source stays intact".write(
                to: url.appendingPathComponent("main.dart"), atomically: true, encoding: .utf8)
        }
        let archive = folder.appendingPathComponent("projects.json")
        let store = ProjectStore(file: archive)
        for url in projectFolders { try store.open(url) }
        XCTAssertNotNil(store.selectedID)
        store.clearSavedProjects()
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertNil(store.selectedID)
        let reopened = ProjectStore(file: archive)
        XCTAssertTrue(reopened.projects.isEmpty)
        XCTAssertNil(reopened.selectedID)
        for url in projectFolders {
            XCTAssertEqual(try String(contentsOf: url.appendingPathComponent("main.dart")), "source stays intact")
            XCTAssertNoThrow(try ProjectStore.validate(url))
        }
        // A cleared project can be saved again normally.
        try reopened.open(projectFolders[0])
        XCTAssertEqual(reopened.projects.count, 1)
    }
    @MainActor func testPersistenceSelectionDeduplicationRelocationAndRemoval() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("проект A")
        let b = folder.appendingPathComponent("проект B")
        for url in [a, b] {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent("ios"), withIntermediateDirectories: true)
            try "name: counter\ndependencies:\n  flutter:\n    sdk: flutter\n".write(
                to: url.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        }
        let archive = folder.appendingPathComponent("projects.json")
        let store = ProjectStore(file: archive)
        var first = try store.open(a)
        first.deviceID = "device-A"
        first.sdkPath = "/SDK with spaces"
        first.launch.arguments = ["--dart-define=NAME=А Б"]
        store.update(first)
        XCTAssertEqual(try store.open(a).id, first.id)
        XCTAssertEqual(store.projects.count, 1)
        let second = try store.open(b)
        store.select(first.id)
        let reopened = ProjectStore(file: archive)
        XCTAssertEqual(reopened.selectedID, first.id)
        XCTAssertEqual(reopened.selected?.sdkPath, first.sdkPath)
        XCTAssertEqual(reopened.selected?.launch.arguments, first.launch.arguments)
        XCTAssertNotEqual(reopened.label(first), reopened.label(second))
        reopened.remove(second.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        try FileManager.default.removeItem(at: a)
        let relocated = try reopened.open(b, replacing: first.id)
        XCTAssertEqual(relocated.id, first.id)
        XCTAssertEqual(relocated.path, b.path)
    }
    @MainActor func testCorruptStoreDoesNotOverwriteEvidence() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("invalid".utf8).write(to: file)
        let store = ProjectStore(file: file)
        XCTAssertNotNil(store.persistenceError)
        store.selectedID = UUID()
        XCTAssertEqual(try String(contentsOf: file), "invalid")
        let backup = try XCTUnwrap(store.recoverPersistence())
        defer { try? FileManager.default.removeItem(at: backup) }
        XCTAssertEqual(try String(contentsOf: backup), "invalid")
        XCTAssertNil(ProjectStore(file: file).persistenceError)
    }
    func testRejectsNonFlutterFolder() { XCTAssertThrowsError(try ProjectStore.validate(URL(fileURLWithPath: "/tmp"))) }
    func testReservedArgumentsAndDebugConfiguration() throws {
        var config = LaunchConfiguration()
        config.arguments = ["--dart-define=TEXT=Привет мир"]
        XCTAssertTrue(try config.validatedArguments().contains("--dart-define=TEXT=Привет мир"))
        for arg in ["--debug", "--profile", "--release", "-dother", "--target=x", "--flavor", "--no-resident", "--"] {
            config.arguments = [arg]
            XCTAssertThrowsError(try config.validatedArguments())
        }
        config.arguments = []
        for name in ["Release", "Profile", "Debugging"] {
            config.buildConfiguration = name
            XCTAssertThrowsError(try config.validatedArguments())
        }
        config.buildConfiguration = "Debug-dev"
        config.scheme = "dev"
        XCTAssertEqual(
            try config.validatedArguments(),
            ["run", "--machine", "--debug", "--target", "lib/main.dart", "--flavor", "dev"])
    }
}

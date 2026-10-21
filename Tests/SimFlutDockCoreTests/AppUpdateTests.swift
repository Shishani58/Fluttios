import CryptoKit
import XCTest

@testable import SimFlutDockCore

final class AppUpdateTests: XCTestCase {
    func testVersionsCompareNumericallyAndRejectUnsupportedTags() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9.9")), try XCTUnwrap(AppVersion("v1.10.0")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.99.99")), try XCTUnwrap(AppVersion("2.0.0")))
        XCTAssertEqual(AppVersion("v1.0.3"), AppVersion("1.0.3"))
        for invalid in ["", "1.0", "1.0.0.0", "1.0.4-beta", "1.0.4+5", "01.0.4", "../1.0.4", "1.-1.0", "1.0.４"] {
            XCTAssertNil(AppVersion(invalid), invalid)
        }
    }

    func testOnlyNewStableReleasesWithMatchingAssetsAreOffered() throws {
        let current = try XCTUnwrap(AppVersion("1.0.3"))
        let update = try XCTUnwrap(AppUpdateService.update(from: release(), currentVersion: current))
        XCTAssertEqual(update.version.description, "1.0.4")
        XCTAssertEqual(update.downloadURL.lastPathComponent, "SimFlutDock-1.0.4.dmg")
        XCTAssertEqual(update.notes, "Bug fixes")
        XCTAssertNil(try AppUpdateService.update(from: release(tag: "v1.0.3"), currentVersion: current))
        XCTAssertNil(try AppUpdateService.update(from: release(tag: "v1.0.2"), currentVersion: current))
        XCTAssertNil(try AppUpdateService.update(from: release(draft: true), currentVersion: current))
        XCTAssertNil(try AppUpdateService.update(from: release(prerelease: true), currentVersion: current))
        for data in [
            release(checksum: false), release(host: "example.com"), release(tag: "v1.0.4-beta"), release(state: "new"),
        ] {
            XCTAssertThrowsError(try AppUpdateService.update(from: data, currentVersion: current))
        }
    }

    func testChecksumIsBoundToInstallerAndRejectsMalformedData() throws {
        let hash = String(repeating: "ab", count: 32)
        XCTAssertEqual(try AppUpdateService.checksum(from: Data("\(hash)  app.dmg\n".utf8), filename: "app.dmg"), hash)
        for value in [
            hash, "\(hash)  other.dmg", "123 app.dmg", "\(String(repeating: "z", count: 64)) app.dmg",
            "\(hash) app.dmg\n\(hash) app.dmg",
        ] {
            XCTAssertThrowsError(try AppUpdateService.checksum(from: Data(value.utf8), filename: "app.dmg"))
        }
    }

    func testVerificationRejectsTruncatedAndTamperedDownloads() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data("installer contents".utf8)
        try data.write(to: file)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertNoThrow(
            try AppUpdateService.verify(file: file, expectedSize: Int64(data.count), expectedChecksum: checksum))
        XCTAssertThrowsError(
            try AppUpdateService.verify(file: file, expectedSize: Int64(data.count + 1), expectedChecksum: checksum))
        XCTAssertThrowsError(
            try AppUpdateService.verify(
                file: file, expectedSize: Int64(data.count), expectedChecksum: String(repeating: "0", count: 64)))
    }

    func testCheckHandlesHTTPFailuresAndMalformedResponses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = AppUpdateService(session: session)
        UpdateURLProtocol.response = (200, release())
        let update = try await service.check(currentVersion: "1.0.3")
        XCTAssertEqual(update?.version.description, "1.0.4")
        for status in [403, 404, 429, 500] {
            UpdateURLProtocol.response = (status, Data())
            do {
                _ = try await service.check(currentVersion: "1.0.3")
                XCTFail("Expected HTTP failure")
            } catch AppUpdateError.unavailable(let actual) { XCTAssertEqual(actual, status) }
        }
        UpdateURLProtocol.response = (200, Data("not JSON".utf8))
        do {
            _ = try await service.check(currentVersion: "1.0.3")
            XCTFail("Expected decoding failure")
        } catch is DecodingError {}
        do {
            _ = try await service.check(currentVersion: "")
            XCTFail("Expected version failure")
        } catch AppUpdateError.invalidVersion {}
    }

    func testOlderReleasesFallBackToAPIWhenManifestIsMissing() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        UpdateURLProtocol.missingManifest = true
        defer {
            session.invalidateAndCancel()
            UpdateURLProtocol.missingManifest = false
        }
        UpdateURLProtocol.response = (200, release())
        let update = try await AppUpdateService(session: session).check(currentVersion: "1.0.3")
        XCTAssertEqual(update?.version.description, "1.0.4")
    }

    private func release(
        tag: String = "v1.0.4", draft: Bool = false, prerelease: Bool = false,
        checksum: Bool = true, host: String = "github.com", state: String = "uploaded"
    ) -> Data {
        let name = "SimFlutDock-\(tag.dropFirst()).dmg"
        let assets = (checksum ? [name, name + ".sha256"] : [name]).map {
            [
                "name": $0, "state": state, "size": 100,
                "browser_download_url": "https://\(host)/Shishani58/Fluttios/releases/download/\(tag)/\($0)",
            ] as [String: Any]
        }
        return try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "draft": draft,
            "prerelease": prerelease, "body": "Bug fixes", "assets": assets,
        ])
    }

    func testPreparedApplicationRequiresMatchingVersionIdentityAndValidSignature() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = try signedApp(in: folder.appendingPathComponent("installed"), version: "1.0.3")
        let candidate = try signedApp(in: folder.appendingPathComponent("candidate"), version: "1.0.4")
        let version = try XCTUnwrap(AppVersion("1.0.4"))
        try await AppUpdateService.validateApplication(candidate, version: version, installed: installed)
        do {
            try await AppUpdateService.validateApplication(
                candidate, version: XCTUnwrap(AppVersion("1.0.5")), installed: installed)
            XCTFail("A mismatched version must be rejected")
        } catch { XCTAssertTrue(error is AppUpdateError) }
        let wrongID = try signedApp(
            in: folder.appendingPathComponent("wrong"), version: "1.0.4", identifier: "com.other.app")
        do {
            try await AppUpdateService.validateApplication(wrongID, version: version, installed: installed)
            XCTFail("A different bundle identifier must be rejected")
        } catch { XCTAssertTrue(error is AppUpdateError) }
        try Data("tampered".utf8).write(to: candidate.appendingPathComponent("Contents/MacOS/SimFlutDock"))
        do {
            try await AppUpdateService.validateApplication(candidate, version: version, installed: installed)
            XCTFail("A damaged signature must be rejected")
        } catch {}
    }

    func testCancelledPreparationDoesNotCreateStagingFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = try signedApp(in: folder, version: "1.0.3")
        let update = try XCTUnwrap(
            AppUpdateService.update(from: release(), currentVersion: XCTUnwrap(AppVersion("1.0.3"))))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AppUpdateService().prepareInstallation(
                installer: folder.appendingPathComponent("missing.dmg"), update: update, destination: installed)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled preparation must not proceed")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["SimFlutDock.app"])
    }

    func testInstallerWaitsForExitAndReplacesAppWithQuotedPaths() throws {
        let fixture = try installerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: "/bin/sleep")
        parent.arguments = ["30"]
        try parent.run()
        defer {
            if parent.isRunning {
                parent.terminate()
                parent.waitUntilExit()
            }
        }
        let installer = try runInstaller(fixture, parentPID: parent.processIdentifier)
        // The helper must not replace files until its parent actually exits.
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertTrue(installer.isRunning)
        XCTAssertEqual(try String(contentsOf: fixture.destination), "old")
        parent.terminate()
        parent.waitUntilExit()
        installer.waitUntilExit()
        XCTAssertEqual(installer.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: fixture.destination), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.staging.path))
    }

    func testInstallerRestoresPreviousVersionIfReplacementFails() throws {
        let fixture = try installerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.application)
        let installer = try runInstaller(fixture, parentPID: Int32.max)
        installer.waitUntilExit()
        XCTAssertEqual(installer.terminationStatus, 1)
        XCTAssertEqual(try String(contentsOf: fixture.destination), "old")
    }

    func testInstallerRestoresPreviousVersionIfRelaunchFails() throws {
        let fixture = try installerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let installer = try runInstaller(fixture, parentPID: Int32.max, failRelaunch: true)
        installer.waitUntilExit()
        XCTAssertEqual(installer.terminationStatus, 1)
        XCTAssertEqual(try String(contentsOf: fixture.destination), "old")
    }

    func testDMGPreparationStagesVerifiedAppWithoutChangingInstalledCopy() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = try signedApp(in: folder.appendingPathComponent("installed"), version: "1.0.3")
        let candidateFolder = folder.appendingPathComponent("release")
        _ = try signedApp(in: candidateFolder, version: "1.0.4")
        let image = folder.appendingPathComponent("update.dmg")
        let create = Process()
        create.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        create.arguments = ["create", "-srcfolder", candidateFolder.path, "-format", "UDZO", image.path]
        create.standardOutput = FileHandle.nullDevice
        create.standardError = FileHandle.nullDevice
        try create.run()
        create.waitUntilExit()
        XCTAssertEqual(create.terminationStatus, 0)
        let update = try XCTUnwrap(
            AppUpdateService.update(from: release(), currentVersion: XCTUnwrap(AppVersion("1.0.3"))))
        let prepared = try await AppUpdateService().prepareInstallation(
            installer: image, update: update, destination: installed)
        XCTAssertEqual(prepared.destination, installed.resolvingSymlinksInPath())
        XCTAssertEqual(
            Bundle(url: installed)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, "1.0.3")
        XCTAssertEqual(
            Bundle(url: prepared.application)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            "1.0.4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.directory.path))
    }

    private struct InstallerFixture {
        let root: URL
        let staging: URL
        let destination: URL
        let application: URL
    }

    private func installerFixture() throws -> InstallerFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Update ' test $() \(UUID().uuidString)")
        let staging = root.appendingPathComponent(".staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("SimFlutDock.app")
        let application = staging.appendingPathComponent("SimFlutDock.app")
        try Data("old".utf8).write(to: destination)
        try Data("new".utf8).write(to: application)
        return InstallerFixture(root: root, staging: staging, destination: destination, application: application)
    }

    private func runInstaller(_ fixture: InstallerFixture, parentPID: Int32, failRelaunch: Bool = false) throws
        -> Process
    {
        // Exercise the production swap script without launching apps or showing alerts.
        let script = PreparedAppUpdate.installerScript
            .replacingOccurrences(of: "/usr/bin/open", with: failRelaunch ? "/usr/bin/false" : "/usr/bin/true")
            .replacingOccurrences(of: "/usr/bin/osascript", with: "/usr/bin/true")
        let url = fixture.root.appendingPathComponent("install.sh")
        try Data(script.utf8).write(to: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            url.path, String(parentPID), fixture.application.path, fixture.destination.path, fixture.staging.path,
            "Installation failed",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func signedApp(in folder: URL, version: String, identifier: String = "com.fluttios.app") throws -> URL {
        let app = folder.appendingPathComponent("SimFlutDock.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist = [
            "CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
            "CFBundleExecutable": "SimFlutDock", "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"), to: contents.appendingPathComponent("MacOS/SimFlutDock"))
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", "--timestamp=none", app.path]
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
        XCTAssertEqual(sign.terminationStatus, 0)
        return app
    }
}

private final class UpdateURLProtocol: URLProtocol {
    static var response: (Int, Data) = (200, Data())
    static var missingManifest = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) =
            Self.missingManifest && request.url == AppUpdateService.manifestURL ? (404, Data()) : Self.response
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

import XCTest
import CryptoKit
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
        for data in [release(checksum: false), release(host: "example.com"), release(tag: "v1.0.4-beta"), release(state: "new")] {
            XCTAssertThrowsError(try AppUpdateService.update(from: data, currentVersion: current))
        }
    }

    func testChecksumIsBoundToInstallerAndRejectsMalformedData() throws {
        let hash = String(repeating: "ab", count: 32)
        XCTAssertEqual(try AppUpdateService.checksum(from: Data("\(hash)  app.dmg\n".utf8), filename: "app.dmg"), hash)
        for value in [hash, "\(hash)  other.dmg", "123 app.dmg", "\(String(repeating: "z", count: 64)) app.dmg", "\(hash) app.dmg\n\(hash) app.dmg"] {
            XCTAssertThrowsError(try AppUpdateService.checksum(from: Data(value.utf8), filename: "app.dmg"))
        }
    }

    func testVerificationRejectsTruncatedAndTamperedDownloads() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data("installer contents".utf8)
        try data.write(to: file)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertNoThrow(try AppUpdateService.verify(file: file, expectedSize: Int64(data.count), expectedChecksum: checksum))
        XCTAssertThrowsError(try AppUpdateService.verify(file: file, expectedSize: Int64(data.count + 1), expectedChecksum: checksum))
        XCTAssertThrowsError(try AppUpdateService.verify(file: file, expectedSize: Int64(data.count), expectedChecksum: String(repeating: "0", count: 64)))
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
        } catch is DecodingError { }
        do {
            _ = try await service.check(currentVersion: "")
            XCTFail("Expected version failure")
        } catch AppUpdateError.invalidVersion { }
    }

    func testOlderReleasesFallBackToAPIWhenManifestIsMissing() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        UpdateURLProtocol.missingManifest = true
        defer { session.invalidateAndCancel(); UpdateURLProtocol.missingManifest = false }
        UpdateURLProtocol.response = (200, release())
        let update = try await AppUpdateService(session: session).check(currentVersion: "1.0.3")
        XCTAssertEqual(update?.version.description, "1.0.4")
    }

    private func release(tag: String = "v1.0.4", draft: Bool = false, prerelease: Bool = false,
                         checksum: Bool = true, host: String = "github.com", state: String = "uploaded") -> Data {
        let name = "SimFlutDock-\(tag.dropFirst()).dmg"
        let assets = (checksum ? [name, name + ".sha256"] : [name]).map {
            ["name": $0, "state": state, "size": 100,
             "browser_download_url": "https://\(host)/Shishani58/Fluttios/releases/download/\(tag)/\($0)"] as [String: Any]
        }
        return try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft,
                                                            "prerelease": prerelease, "body": "Bug fixes", "assets": assets])
    }
}

private final class UpdateURLProtocol: URLProtocol {
    static var response: (Int, Data) = (200, Data())
    static var missingManifest = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.missingManifest && request.url == AppUpdateService.manifestURL ? (404, Data()) : Self.response
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

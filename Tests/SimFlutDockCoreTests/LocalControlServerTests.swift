import Darwin
import XCTest

@testable import SimFlutDockCore

final class LocalControlServerTests: XCTestCase {
    // Real sockets are the contract here: framing, permissions and stalled peers cannot be mocked.
    @MainActor func testFramedResponseRemainsAvailableBesideIdlePeerAndDuplicateStart() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("control.sock")
        let server = LocalControlServer(socketURL: url) { request in
            XCTAssertEqual(String(decoding: request, as: UTF8.self), "{\"method\":\"list_sessions\"}")
            return Data("{\"sessions\":[]}".utf8)
        }
        try server.start()
        defer { server.stop() }
        let idle = try connect(url)
        defer { Darwin.close(idle) }
        let duplicate = LocalControlServer(socketURL: url) { _ in Data() }
        XCTAssertThrowsError(try duplicate.start())
        duplicate.stop()
        let response = try await Task.detached {
            try Self.exchange(url, request: "{\"method\":\"list_sessions\"}\n")
        }.value
        XCTAssertEqual(response, "{\"sessions\":[]}\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try duplicate.start()
        duplicate.stop()
    }

    @MainActor func testOversizedRequestIsDisconnectedWithoutInvokingHandler() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("control.sock")
        var handled = false
        let server = LocalControlServer(socketURL: url) { _ in
            handled = true
            return Data()
        }
        try server.start()
        defer { server.stop() }
        let response = try await Task.detached {
            try Self.exchange(url, request: String(repeating: "x", count: 65_537) + "\n")
        }.value
        XCTAssertEqual(response, "")
        XCTAssertFalse(handled)
    }

    @MainActor func testRejectsInsecureDirectoryAndSymlinkWithoutRemovingTarget() throws {
        let invalid = LocalControlServer(socketURL: URL(string: "relative.sock")!) { _ in Data() }
        XCTAssertThrowsError(try invalid.start())
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let insecure = directory.appendingPathComponent("insecure")
        try FileManager.default.createDirectory(at: insecure, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: insecure.path)
        let unsafeServer = LocalControlServer(socketURL: insecure.appendingPathComponent("control.sock")) { _ in Data()
        }
        XCTAssertThrowsError(try unsafeServer.start())
        let target = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: target)
        let url = directory.appendingPathComponent("control.sock")
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let server = LocalControlServer(socketURL: url) { _ in Data() }
        XCTAssertThrowsError(try server.start())
        XCTAssertEqual(try String(contentsOf: target), "keep")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), target.path)
    }

    @MainActor func testRecoversStaleSocketButStopPreservesReplacementPath() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("control.sock")
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        let bound = withAddress(url) { Darwin.bind(fd, $0, $1) }
        Darwin.close(fd)
        XCTAssertEqual(bound, 0)
        let server = LocalControlServer(socketURL: url) { _ in Data() }
        try server.start()
        try FileManager.default.removeItem(at: url)
        try Data("replacement".utf8).write(to: url)
        server.stop()
        XCTAssertEqual(try String(contentsOf: url), "replacement")
    }

    private func temporaryDirectory() throws -> URL {
        // Stay outside macOS's /var alias: the transport intentionally rejects symlink traversal.
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build")
            .appendingPathComponent("fluttios-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return directory
    }

    private func connect(_ url: URL) throws -> Int32 { try Self.openConnection(url) }

    private static func openConnection(_ url: URL) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw socketError() }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        guard withAddress(url, { Darwin.connect(fd, $0, $1) }) == 0 else {
            let error = socketError()
            Darwin.close(fd)
            throw error
        }
        return fd
    }

    private static func exchange(_ url: URL, request: String) throws -> String {
        let fd = try openConnection(url)
        defer { Darwin.close(fd) }
        let data = Data(request.utf8)
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset)
            }
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else { throw socketError() }
            offset += written
        }
        var response = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 || (count < 0 && errno == ECONNRESET) { break }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw socketError() }
            response.append(contentsOf: bytes.prefix(count))
            if response.contains(10) { break }
        }
        return String(decoding: response, as: UTF8.self)
    }

    private func withAddress<T>(_ url: URL, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        Self.withAddress(url, body)
    }

    private static func withAddress<T>(_ url: URL, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = Array(url.path.utf8) + [0]
        precondition(path.count <= MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    private static func socketError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

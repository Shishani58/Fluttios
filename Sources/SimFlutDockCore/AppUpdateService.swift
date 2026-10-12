import Foundation
import CryptoKit

/// Release tags and bundle versions use the repository's major.minor.patch format.
public struct AppVersion: Comparable, Equatable, Sendable {
    private let components: [Int]
    public let description: String

    public init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.allSatisfy({ $0.count == 1 || !$0.hasPrefix("0") }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        components = numbers
        description = text
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public struct AppUpdate: Sendable, Equatable {
    public let version: AppVersion
    public let downloadURL: URL
    public let checksumURL: URL
    public let size: Int64
    public let notes: String
}

public enum AppUpdateError: Error, LocalizedError {
    case invalidVersion, invalidRelease, unavailable(Int), invalidChecksum, damagedDownload

    public var errorDescription: String? {
        switch self {
        case .invalidVersion: return L10n.text("Could not determine the installed version. Open the built SimFlutDock.app.")
        case .invalidRelease: return L10n.text("The release does not contain a compatible installer and checksum. Try again later.")
        case .unavailable(let status): return L10n.text("The update server returned HTTP {0}. Try again later.", String(status))
        case .invalidChecksum: return L10n.text("The installer checksum is missing or invalid. Try again later.")
        case .damagedDownload: return L10n.text("The downloaded installer failed verification. Please download it again.")
        }
    }
}

public actor AppUpdateService {
    public static let manifestURL = URL(string: "https://github.com/Shishani58/Fluttios/releases/latest/download/app-update.json")!
    public static let endpoint = URL(string: "https://api.github.com/repos/Shishani58/Fluttios/releases/latest")!
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func check(currentVersion: String) async throws -> AppUpdate? {
        guard let current = AppVersion(currentVersion) else { throw AppUpdateError.invalidVersion }
        let manifestRequest = URLRequest(url: Self.manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (manifest, manifestResponse) = try await session.data(for: manifestRequest)
        if (manifestResponse as? HTTPURLResponse)?.statusCode != 404 {
            try Self.validate(manifestResponse)
            return try Self.update(from: manifest, currentVersion: current)
        }
        // Releases published before app-update.json was introduced still work through the API.
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SimFlutDock/\(current.description)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try Self.update(from: data, currentVersion: current)
    }

    public static func update(from data: Data, currentVersion: AppVersion) throws -> AppUpdate? {
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        guard let version = AppVersion(release.tag_name) else { throw AppUpdateError.invalidRelease }
        guard version > currentVersion else { return nil }
        let name = "SimFlutDock-\(version.description).dmg"
        func asset(_ name: String) -> Release.Asset? {
            release.assets.first { asset in
                asset.name == name && asset.state == "uploaded" && asset.size > 0 &&
                asset.browser_download_url.absoluteString ==
                    "https://github.com/Shishani58/Fluttios/releases/download/\(release.tag_name)/\(name)"
            }
        }
        guard let installer = asset(name), let checksum = asset(name + ".sha256") else {
            throw AppUpdateError.invalidRelease
        }
        return AppUpdate(version: version, downloadURL: installer.browser_download_url,
                         checksumURL: checksum.browser_download_url, size: installer.size,
                         notes: release.body ?? "")
    }

    /// Returns a verified DMG in a unique Downloads subdirectory; never overwrites a user file.
    public func download(_ update: AppUpdate, downloadsDirectory: URL) async throws -> URL {
        let (checksum, checksumResponse) = try await session.data(for: URLRequest(url: update.checksumURL, timeoutInterval: 30))
        try Self.validate(checksumResponse)
        let expected = try Self.checksum(from: checksum, filename: update.downloadURL.lastPathComponent)
        let (temporary, response) = try await session.download(for: URLRequest(url: update.downloadURL, timeoutInterval: 300))
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.validate(response)
        try Task.checkCancellation()
        try Self.verify(file: temporary, expectedSize: update.size, expectedChecksum: expected)
        try Task.checkCancellation()
        let folder = downloadsDirectory.appendingPathComponent("SimFlutDock-\(update.version.description)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(update.downloadURL.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func checksum(from data: Data, filename: String) throws -> String {
        guard data.count < 4096, let text = String(data: data, encoding: .utf8) else { throw AppUpdateError.invalidChecksum }
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[1] == Substring(filename), parts[0].count == 64,
              parts[0].allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw AppUpdateError.invalidChecksum }
        return parts[0].lowercased()
    }

    static func verify(file: URL, expectedSize: Int64, expectedChecksum: String) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: Int64 = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            size += Int64(data.count)
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard size == expectedSize, digest == expectedChecksum else { throw AppUpdateError.damagedDownload }
    }

    private static func validate(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AppUpdateError.unavailable(status) }
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let state: String
            let size: Int64
            let browser_download_url: URL
        }
    }
}

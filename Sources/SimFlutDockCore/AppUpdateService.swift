import CryptoKit
import Foundation
import Security

/// Release tags and bundle versions use the repository's major.minor.patch format.
public struct AppVersion: Comparable, Equatable, Sendable {
    private let components: [Int]
    public let description: String

    public init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
            parts.allSatisfy({ $0.count == 1 || !$0.hasPrefix("0") })
        else { return nil }
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
    case invalidVersion, invalidRelease
    case unavailable(Int)
    case invalidChecksum, damagedDownload

    public var errorDescription: String? {
        switch self {
        case .invalidVersion:
            return L10n.text("Could not determine the installed version. Open the built SimFlutDock.app.")
        case .invalidRelease:
            return L10n.text("The release does not contain a compatible installer and checksum. Try again later.")
        case .unavailable(let status):
            return L10n.text("The update server returned HTTP {0}. Try again later.", String(status))
        case .invalidChecksum: return L10n.text("The installer checksum is missing or invalid. Try again later.")
        case .damagedDownload:
            return L10n.text("The downloaded installer failed verification. Please download it again.")
        }
    }
}

public actor AppUpdateService {
    public static let manifestURL = URL(
        string: "https://github.com/Shishani58/Fluttios/releases/latest/download/app-update.json")!
    public static let endpoint = URL(string: "https://api.github.com/repos/Shishani58/Fluttios/releases/latest")!
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func check(currentVersion: String) async throws -> AppUpdate? {
        guard let current = AppVersion(currentVersion) else { throw AppUpdateError.invalidVersion }
        let manifestRequest = URLRequest(
            url: Self.manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
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
        guard let version = AppVersion(release.tagName) else { throw AppUpdateError.invalidRelease }
        guard version > currentVersion else { return nil }
        let name = "SimFlutDock-\(version.description).dmg"
        func asset(_ name: String) -> Release.Asset? {
            release.assets.first { asset in
                asset.name == name && asset.state == "uploaded" && asset.size > 0
                    && asset.browserDownloadURL.absoluteString
                        == "https://github.com/Shishani58/Fluttios/releases/download/\(release.tagName)/\(name)"
            }
        }
        guard let installer = asset(name), let checksum = asset(name + ".sha256") else {
            throw AppUpdateError.invalidRelease
        }
        return AppUpdate(
            version: version, downloadURL: installer.browserDownloadURL,
            checksumURL: checksum.browserDownloadURL, size: installer.size,
            notes: release.body ?? "")
    }

    /// Returns a verified DMG in a unique Downloads subdirectory; never overwrites a user file.
    public func download(_ update: AppUpdate, downloadsDirectory: URL) async throws -> URL {
        let (checksum, checksumResponse) = try await session.data(
            for: URLRequest(url: update.checksumURL, timeoutInterval: 30))
        try Self.validate(checksumResponse)
        let expected = try Self.checksum(from: checksum, filename: update.downloadURL.lastPathComponent)
        let (temporary, response) = try await session.download(
            for: URLRequest(url: update.downloadURL, timeoutInterval: 300))
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.validate(response)
        try Task.checkCancellation()
        try Self.verify(file: temporary, expectedSize: update.size, expectedChecksum: expected)
        try Task.checkCancellation()
        let folder = downloadsDirectory.appendingPathComponent(
            "SimFlutDock-\(update.version.description)-\(UUID().uuidString)", isDirectory: true)
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
        guard data.count < 4096, let text = String(data: data, encoding: .utf8) else {
            throw AppUpdateError.invalidChecksum
        }
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[1] == Substring(filename), parts[0].count == 64,
            parts[0].allSatisfy({ $0.isASCII && $0.isHexDigit })
        else { throw AppUpdateError.invalidChecksum }
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
        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, body, assets
        }
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable {
            private enum CodingKeys: String, CodingKey {
                case name, state, size
                case browserDownloadURL = "browser_download_url"
            }
            let name: String
            let state: String
            let size: Int64
            let browserDownloadURL: URL
        }
    }
}

/// A private staging directory on the destination volume allows a rename-based swap.
/// The downloaded DMG is never opened in Finder or modified.
public struct PreparedAppUpdate: Sendable {
    public let directory: URL
    public let application: URL
    public let destination: URL

    public func launchInstaller(parentPID: Int32) throws {
        let script = directory.appendingPathComponent("install.sh")
        try Data(Self.installerScript.utf8).write(to: script, options: .atomic)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path, String(parentPID), application.path, destination.path, directory.path,
            L10n.text(
                "The update could not be installed. Your previous version has been preserved. Please try again from Settings."
            ),
        ]
        let log = directory.appendingPathComponent("install.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }

    // Paths are positional arguments, never interpolated into shell source.
    static let installerScript = #"""
        #!/bin/sh
        set -eu
        parent="$1"
        staged="$2"
        destination="$3"
        directory="$4"
        failureMessage="$5"
        backup="$directory/Previous.app"
        moved=0
        installed=0
        failed() {
            trap - EXIT
            if [ "$moved" = 1 ]; then
                if [ "$installed" = 1 ]; then /bin/rm -rf "$destination"; fi
                /bin/mv "$backup" "$destination" || exit 1
            fi
            /usr/bin/osascript - "$failureMessage" <<'APPLESCRIPT' || true
        on run argv
            display alert "SimFlutDock" message (item 1 of argv) as critical
        end run
        APPLESCRIPT
            /usr/bin/open "$destination" || true
            exit 1
        }
        trap failed EXIT
        attempts=0
        while /bin/kill -0 "$parent" 2>/dev/null; do
            attempts=$((attempts + 1))
            # Never replace a running app if termination was interrupted.
            if [ "$attempts" -ge 120 ]; then trap - EXIT; exit 1; fi
            /bin/sleep 1
        done
        /bin/mv "$destination" "$backup"
        moved=1
        /bin/mv "$staged" "$destination"
        installed=1
        /usr/bin/open "$destination"
        trap - EXIT
        /bin/rm -rf "$directory"
        """#
}

extension AppUpdateService {
    public func prepareInstallation(installer: URL, update: AppUpdate, destination: URL) async throws
        -> PreparedAppUpdate
    {
        try Task.checkCancellation()
        let fm = FileManager.default
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard destination.pathExtension == "app", Bundle(url: destination)?.bundleIdentifier == "com.fluttios.app",
            !destination.path.hasPrefix("/Volumes/"),
            !destination.path.contains("/AppTranslocation/"),
            fm.isWritableFile(atPath: destination.path),
            fm.isWritableFile(atPath: destination.deletingLastPathComponent().path)
        else {
            throw SimFlutDockError.message(
                L10n.text("Move SimFlutDock to a writable Applications folder, then try updating again."))
        }
        let directory = destination.deletingLastPathComponent()
            .appendingPathComponent(".SimFlutDock-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var prepared = false
        defer { if !prepared { try? fm.removeItem(at: directory) } }
        let mount = directory.appendingPathComponent("Volume", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: false)
        let application = directory.appendingPathComponent("SimFlutDock.app", isDirectory: true)
        do {
            try await Self.updateCommand(
                "/usr/bin/hdiutil",
                ["attach", installer.path, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path])
            try await Self.updateCommand(
                "/usr/bin/ditto", [mount.appendingPathComponent("SimFlutDock.app").path, application.path])
            try await Self.validateApplication(application, version: update.version, installed: destination)
        } catch {
            // Cancellation can race with mounting. Cleanup must run even in a cancelled task.
            await Self.detachVolume(mount)
            throw error
        }
        await Self.detachVolume(mount)
        try Task.checkCancellation()
        prepared = true
        return PreparedAppUpdate(directory: directory, application: application, destination: destination)
    }

    static func validateApplication(_ application: URL, version: AppVersion, installed: URL) async throws {
        guard let bundle = Bundle(url: application), bundle.bundleIdentifier == "com.fluttios.app",
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version.description,
            let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path)
        else {
            throw AppUpdateError.damagedDownload
        }
        try await updateCommand(
            "/usr/bin/codesign", ["--verify", "--deep", "--strict", "--all-architectures", application.path])
        // Certificate-signed installations must retain their designated identity.
        // Ad-hoc releases have a per-build hash requirement and rely on the verified release checksum.
        var current: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(installed as CFURL, [], &current) == errSecSuccess, let current,
            SecCodeCopySigningInformation(current, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
            let info = info as? [String: Any]
        else { throw AppUpdateError.damagedDownload }
        if info[kSecCodeInfoCertificates as String] != nil {
            var requirement: SecRequirement?
            var candidate: SecStaticCode?
            guard SecCodeCopyDesignatedRequirement(current, [], &requirement) == errSecSuccess,
                SecStaticCodeCreateWithPath(application as CFURL, [], &candidate) == errSecSuccess, let candidate,
                SecStaticCodeCheckValidity(candidate, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
                    == errSecSuccess
            else {
                throw AppUpdateError.damagedDownload
            }
        }
    }

    private static func detachVolume(_ mount: URL) async {
        await Task.detached {
            do {
                try await updateCommand("/usr/bin/hdiutil", ["detach", mount.path], timeout: 30)
            } catch {
                try? await updateCommand("/usr/bin/hdiutil", ["detach", "-force", mount.path], timeout: 30)
            }
        }.value
    }

    private static func updateCommand(_ executable: String, _ arguments: [String], timeout: TimeInterval = 120)
        async throws
    {
        let result = try await ToolRunner.run(executable, arguments, timeout: timeout)
        guard result.status == 0 else {
            throw SimFlutDockError.message(
                L10n.text(
                    "Could not prepare the update for automatic installation. Check available disk space and folder permissions, then try again."
                ))
        }
    }
}

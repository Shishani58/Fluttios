import Foundation
import Darwin

public struct ToolResult {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    public var text: String { String(decoding: stdout + stderr, as: UTF8.self) }
    public func checked() throws -> ToolResult {
        guard status == 0 else { throw FluttiosError.message(text.isEmpty ? L10n.text("Tool exited with code {0}.", "\(status)") : text) }
        return self
    }
}

private final class ToolJob: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        // Foundation gives Process its own process group. Never signal the
        // application's group if a platform does not provide that isolation.
        if getpgid(pid) == pid { kill(-pid, SIGKILL) }
        else { kill(pid, SIGKILL) }
    }
    func run(executable: String, arguments: [String], directory: String?, environment: [String: String]) throws -> ToolResult {
        let stdout = Pipe(), stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.environment = environment
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        process.standardOutput = stdout; process.standardError = stderr
        let outFD = stdout.fileHandleForReading.fileDescriptor
        let errFD = stderr.fileHandleForReading.fileDescriptor
        for fd in [outFD, errFD] {
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        defer {
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
        }
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        var out = Data(), err = Data()
        func drain(_ fd: Int32, into output: inout Data) {
            var bytes = [UInt8](repeating: 0, count: 16_384)
            // A continuously writing tool must not prevent checking cancellation.
            for _ in 0..<64 {
                let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return }
                let retained = min(count, max(0, 8_000_000 - output.count))
                output.append(contentsOf: bytes.prefix(retained))
            }
        }
        while process.isRunning {
            drain(outFD, into: &out); drain(errFD, into: &err)
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        // Drain buffered bytes without waiting for EOF: a descendant may have
        // inherited the pipe even after the parent has exited.
        drain(outFD, into: &out); drain(errFD, into: &err)
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        return ToolResult(status: process.terminationStatus, stdout: out, stderr: err)
    }
}

public enum ToolRunner {
    public static func run(_ executable: String, _ arguments: [String], directory: String? = nil,
                           environment: [String: String] = FlutterSDKResolver.environment(), timeout: TimeInterval = 60) async throws -> ToolResult {
        let job = ToolJob()
        let timer = Task { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); if !Task.isCancelled { job.cancel() } }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            do {
                return try await Task.detached { try job.run(executable: executable, arguments: arguments, directory: directory, environment: environment) }.value
            } catch is CancellationError {
                if Task.isCancelled { throw CancellationError() }
                throw FluttiosError.timeout(executable)
            }
        }, onCancel: { job.cancel() })
    }
}

public enum FlutterSDKResolver {
    public static func developerDirectory() -> String? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], fm.fileExists(atPath: env + "/Platforms/iPhoneSimulator.platform") { return env }
        let selection = URL(fileURLWithPath: "/var/db/xcode_select_link").resolvingSymlinksInPath().path
        if fm.fileExists(atPath: selection + "/Platforms/iPhoneSimulator.platform") { return selection }
        let applications = (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
        for app in applications.filter({ $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }).sorted() {
            let path = "/Applications/\(app)/Contents/Developer"
            if fm.fileExists(atPath: path + "/Platforms/iPhoneSimulator.platform") { return path }
        }
        return nil
    }
    public static func environment(sdk: String? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let additional = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", home + "/.pub-cache/bin"]
        env["PATH"] = ([sdk.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }].compactMap { $0 } + additional + [(env["PATH"] ?? "")]).joined(separator: ":")
        if let developer = developerDirectory() { env["DEVELOPER_DIR"] = developer }
        env["FLUTTER_SUPPRESS_ANALYTICS"] = "true"
        return env
    }
    public static func resolve(project: Project, global: String?) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let explicit = project.sdkPath?.isEmpty == false ? project.sdkPath : (global?.isEmpty == false ? global : nil)
        let candidates = explicit.map { [$0] } ?? [project.path + "/.fvm/flutter_sdk", "/opt/homebrew/bin/flutter", "/usr/local/bin/flutter", home + "/flutter", home + "/development/flutter", home + "/Developer/flutter"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/flutter" }
        for candidate in candidates {
            let expanded = NSString(string: candidate).expandingTildeInPath
            let executable = expanded.hasSuffix("/flutter") && FileManager.default.isExecutableFile(atPath: expanded) ? expanded : expanded + "/bin/flutter"
            if FileManager.default.isExecutableFile(atPath: executable) { return URL(fileURLWithPath: executable).resolvingSymlinksInPath().path }
        }
        throw FluttiosError.message(L10n.text("Flutter SDK not found. Select the SDK folder in settings. For FVM, select the project's .fvm/flutter_sdk or an installed SDK version."))
    }
    public static func check(_ executable: String) async throws -> String {
        let flutter = try await ToolRunner.run(executable, ["--version", "--machine"], environment: environment(sdk: executable), timeout: 45).checked()
        guard developerDirectory() != nil else { throw FluttiosError.message(L10n.text("Full Xcode installation not found. Install and open Xcode, accept the license, and install an iOS Simulator runtime.")) }
        _ = try await ToolRunner.run("/usr/bin/xcrun", ["--find", "simctl"]).checked()
        return flutter.text
    }
}

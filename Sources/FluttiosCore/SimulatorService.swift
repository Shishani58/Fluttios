import Foundation
import AppKit
import Combine
import Darwin

public struct SimulatorHostProcess {
    public let application: NSRunningApplication
    public let processIdentifier: pid_t
    public var isHidden: Bool { application.isHidden }
    public var localizedName: String? { application.localizedName }
}

public enum SimulatorHost {
    public static let bundleIDs = ["com.apple.iphonesimulator", "com.apple.dt.Devices"]
    public static var runningApplications: [NSRunningApplication] {
        bundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    }
    @MainActor private static var resolvedPIDs: [String: pid_t] = [:]
    @MainActor public static var runningProcesses: [SimulatorHostProcess] {
        runningApplications.flatMap { application -> [SimulatorHostProcess] in
            if application.processIdentifier > 0 {
                return [SimulatorHostProcess(application: application, processIdentifier: application.processIdentifier)]
            }
            // Device Hub on macOS 27 can have a valid Launch Services record
            // whose NSRunningApplication PID is -1. Resolve only its exact executable.
            guard let executable = application.executableURL?.resolvingSymlinksInPath().path else { return [] }
            if let pid = resolvedPIDs[executable], processPath(pid) == executable {
                return [SimulatorHostProcess(application: application, processIdentifier: pid)]
            }
            resolvedPIDs.removeValue(forKey: executable)
            let capacity = Int(proc_listallpids(nil, 0)) + 64
            guard capacity > 64 else { return [] }
            var pids = [pid_t](repeating: 0, count: capacity)
            let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
            guard count > 0 else { return [] }
            let matches = pids.prefix(min(Int(count), capacity)).filter { $0 > 0 && processPath($0) == executable }
            if matches.count == 1 { resolvedPIDs[executable] = matches.first }
            return matches.map { SimulatorHostProcess(application: application, processIdentifier: $0) }
        }
    }
    private static func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let count = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard count > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
    }
    public static func applicationURL(developer: String) throws -> URL {
        let classic = URL(fileURLWithPath: developer + "/Applications/Simulator.app")
        let hub = URL(fileURLWithPath: developer).deletingLastPathComponent().appendingPathComponent("Applications/DeviceHub.app")
        if FileManager.default.fileExists(atPath: classic.path) { return classic }
        if FileManager.default.fileExists(atPath: hub.path) { return hub }
        throw FluttiosError.message(L10n.text("Simulator / Device Hub not found in the selected Xcode."))
    }
}

public enum SimulatorToolCommand {
    public static func arguments(device: SimulatorDevice, operation: String, value: String) throws -> [String] {
        guard device.isIOSSimulator, device.isAvailable, device.state == "Booted", !device.id.isEmpty,
              device.id != "booted" else {
            throw FluttiosError.message(L10n.text("Select a running iOS Simulator in project settings."))
        }
        if operation == "openurl" {
            return ["simctl", "openurl", device.id, try SavedDeepLink.validatedURL(value)]
        }
        guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw FluttiosError.message(L10n.text("Could not determine the app's bundle identifier."))
        }
        switch operation {
        case "container": return ["simctl", "get_app_container", device.id, value, "data"]
        case "permissions": return ["simctl", "privacy", device.id, "reset", "all", value]
        default: throw FluttiosError.message(L10n.text("Unknown simulator action."))
        }
    }
}

@MainActor public final class SimulatorService: ObservableObject {
    @Published public private(set) var devices: [SimulatorDevice] = []
    @Published public private(set) var error: String?
    @Published public private(set) var refreshing = false
    public init() {}
    public func refresh(project: Project? = nil, globalSDK: String? = nil) async {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        var discovered: [SimulatorDevice] = []
        var failures: [String] = []
        do {
            let result = try await ToolRunner.run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"], timeout: 20).checked()
            struct List: Decodable { let devices: [String: [SimulatorDevice]] }
            let list = try JSONDecoder().decode(List.self, from: result.stdout)
            discovered = list.devices.flatMap { runtime, values in
                values.filter { $0.isAvailable && runtime.contains("iOS") }.map { device in
                    var device = device; device.runtime = runtime.components(separatedBy: ".").last?.replacingOccurrences(of: "-", with: " "); return device
                }
            }.sorted { $0.name < $1.name }
        } catch { failures.append(L10n.text("Simulators: ") + error.localizedDescription) }
        do {
            let sdkProject = project ?? Project(name: L10n.text("Devices"), path: FileManager.default.homeDirectoryForCurrentUser.path)
            let sdk = try FlutterSDKResolver.resolve(project: sdkProject, global: globalSDK)
            let result = try await ToolRunner.run(sdk, ["devices", "--machine", "--device-timeout", "5"], directory: project?.path, environment: FlutterSDKResolver.environment(sdk: sdk), timeout: 30).checked()
            let flutterDevices = try SimulatorDevice.flutterDevices(from: result.stdout)
            let knownIDs = Set(discovered.map(\.id))
            discovered += flutterDevices.filter { !knownIDs.contains($0.id) }
        } catch { failures.append(L10n.text("Flutter devices: ") + error.localizedDescription) }
        devices = discovered.sorted { $0.name < $1.name }
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
    public func boot(_ device: SimulatorDevice) async throws {
        guard device.isIOSSimulator else { return }
        if device.state != "Booted" {
            let result = try await ToolRunner.run("/usr/bin/xcrun", ["simctl", "boot", device.id], timeout: 30)
            if result.status != 0 && !result.text.contains("current state: Booted") { _ = try result.checked() }
        }
        guard let developer = FlutterSDKResolver.developerDirectory() else { throw FluttiosError.message(L10n.text("Install the full version of Xcode.")) }
        let simulatorURL = try SimulatorHost.applicationURL(developer: developer)
        let config = NSWorkspace.OpenConfiguration()
        if simulatorURL.lastPathComponent == "Simulator.app" { config.arguments = ["-CurrentDeviceUDID", device.id] }
        try await NSWorkspace.shared.openApplication(at: simulatorURL, configuration: config)
        _ = try await ToolRunner.run("/usr/bin/xcrun", ["simctl", "bootstatus", device.id, "-b"], timeout: 180).checked()
    }
    public func foreground(deviceID: String, bundleID: String) async throws {
        // simctl launch (without --terminate-running-process) foregrounds the existing app.
        _ = try await ToolRunner.run("/usr/bin/xcrun", ["simctl", "launch", deviceID, bundleID], timeout: 20).checked()
        SimulatorHost.runningApplications.first?.activate(options: [])
    }
    public func currentSimulator(id: String) async throws -> SimulatorDevice {
        let result = try await ToolRunner.run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"], timeout: 20).checked()
        struct List: Decodable { let devices: [String: [SimulatorDevice]] }
        let list = try JSONDecoder().decode(List.self, from: result.stdout)
        guard let device = list.devices.filter({ $0.key.contains("iOS") }).values.flatMap({ $0 })
            .first(where: { $0.id == id && $0.isAvailable }) else {
            throw FluttiosError.message(L10n.text("The project's simulator is unavailable. Select an iOS Simulator in project settings."))
        }
        return device
    }
    public func openDeepLink(_ url: String, device: SimulatorDevice) async throws {
        let args = try SimulatorToolCommand.arguments(device: device, operation: "openurl", value: url)
        _ = try await ToolRunner.run("/usr/bin/xcrun", args, timeout: 20).checked()
        SimulatorHost.runningApplications.first?.activate(options: [])
    }
    public func dataContainer(bundleID: String, device: SimulatorDevice) async throws -> URL {
        let args = try SimulatorToolCommand.arguments(device: device, operation: "container", value: bundleID)
        let result = try await ToolRunner.run("/usr/bin/xcrun", args, timeout: 20).checked()
        let path = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        var directory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else {
            throw FluttiosError.message(L10n.text("Data folder unavailable. Install the app on the selected simulator using Run."))
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    public func resetPermissions(bundleID: String, device: SimulatorDevice) async throws {
        let args = try SimulatorToolCommand.arguments(device: device, operation: "permissions", value: bundleID)
        // Verify this application is installed before resetting its permissions.
        _ = try await dataContainer(bundleID: bundleID, device: device)
        _ = try await ToolRunner.run("/usr/bin/xcrun", args, timeout: 20).checked()
    }
    public func bundleIdentifier(_ project: Project, device: SimulatorDevice? = nil) async throws -> String {
        if let device, device.targetPlatform != "ios" {
            return URL(fileURLWithPath: project.path).resolvingSymlinksInPath().path
        }
        let args = ["xcodebuild", "-project", "ios/Runner.xcodeproj", "-scheme", project.launch.scheme,
                    "-configuration", project.launch.buildConfiguration, "-sdk", device?.isPhysical == true ? "iphoneos" : "iphonesimulator", "-showBuildSettings", "-json"]
        let result = try await ToolRunner.run("/usr/bin/xcrun", args, directory: project.path, timeout: 90).checked()
        guard let rows = try JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]] else { throw FluttiosError.message(L10n.text("Xcode did not return project settings.")) }
        let ids = Set(rows.compactMap { row -> String? in
            guard let settings = row["buildSettings"] as? [String: Any], settings["PRODUCT_TYPE"] as? String == "com.apple.product-type.application" else { return nil }
            return settings["PRODUCT_BUNDLE_IDENTIFIER"] as? String
        })
        guard ids.count == 1, let id = ids.first, !id.isEmpty, !id.contains("$("), !id.contains(" ") else {
            throw FluttiosError.message(L10n.text("Could not determine a unique bundle identifier. Check the scheme and Xcode configuration in project settings."))
        }
        return id
    }
}

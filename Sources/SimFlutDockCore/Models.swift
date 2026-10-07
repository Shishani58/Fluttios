import Foundation
import CoreGraphics

public enum LaunchMode: String, Codable, CaseIterable {
    case debug, profile, release
    public var title: String { rawValue.capitalized }
    public func supports(_ device: SimulatorDevice?) -> Bool { self == .debug || (device != nil && device?.isEmulator == false) }
}

public struct LaunchConfiguration: Codable, Equatable {
    public var mode: LaunchMode = .debug
    public var entrypoint = "lib/main.dart"
    public var arguments: [String] = []
    public var scheme = "Runner"
    public var buildConfiguration = "Debug"
    public init() {}
    public func usingProjectDefaults(mode: LaunchMode? = nil) -> LaunchConfiguration {
        var configuration = LaunchConfiguration()
        configuration.setMode(mode ?? self.mode)
        return configuration
    }
    private enum CodingKeys: String, CodingKey { case mode, entrypoint, arguments, scheme, buildConfiguration }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decodeIfPresent(LaunchMode.self, forKey: .mode) ?? .debug
        entrypoint = try values.decode(String.self, forKey: .entrypoint)
        arguments = try values.decode([String].self, forKey: .arguments)
        scheme = try values.decode(String.self, forKey: .scheme)
        buildConfiguration = try values.decode(String.self, forKey: .buildConfiguration)
    }
    public mutating func setMode(_ mode: LaunchMode) {
        let oldPrefix = self.mode.title
        let suffix = buildConfiguration.lowercased().hasPrefix(oldPrefix.lowercased() + "-") ? String(buildConfiguration.dropFirst(oldPrefix.count)) : ""
        self.mode = mode; buildConfiguration = mode.title + suffix
    }
    public func validatedArguments(for device: SimulatorDevice? = nil) throws -> [String] {
        let reserved = ["--debug", "--release", "--profile", "--machine", "--no-machine", "--start-paused", "--no-resident", "--device-id", "-d", "--target", "-t", "--flavor", "--use-application-binary", "--help", "-h"]
        guard !entrypoint.isEmpty, !entrypoint.hasPrefix("-"), !scheme.isEmpty,
              (buildConfiguration.lowercased() == mode.rawValue || buildConfiguration.lowercased().hasPrefix(mode.rawValue + "-")) else {
            throw SimFlutDockError.message(L10n.text("Specify an entrypoint, scheme, and {0} or {1}-flavor configuration.", "\(mode.title)", "\(mode.title)"))
        }
        if let device, !mode.supports(device) { throw SimFlutDockError.message(L10n.text("{0} is unavailable on this simulator. Choose Debug or a physical device.", "\(mode.title)")) }
        guard !arguments.contains(where: { arg in reserved.contains(where: { arg == $0 || arg.hasPrefix($0 + "=") }) || arg == "--" || (arg.hasPrefix("-d") && !arg.hasPrefix("--")) || (arg.hasPrefix("-t") && !arg.hasPrefix("--")) }) else {
            throw SimFlutDockError.message(L10n.text("The app sets the launch mode, device, entrypoint, and flavor. Remove conflicting arguments."))
        }
        var result = ["run", "--machine", "--" + mode.rawValue, "--target", entrypoint]
        if scheme != "Runner" { result += ["--flavor", scheme] }
        return result + arguments
    }
}

public struct SavedDeepLink: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var url: String
    public init(id: UUID = UUID(), name: String = "", url: String = "") {
        self.id = id; self.name = name; self.url = url
    }
    public static func validatedURL(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let url = URL(string: value), let scheme = url.scheme, !scheme.isEmpty,
              !["file", "data", "javascript"].contains(scheme.lowercased()),
              (!["http", "https"].contains(scheme.lowercased()) || !(url.host ?? "").isEmpty) else {
            throw SimFlutDockError.message(L10n.text("Enter a complete URL with a scheme, such as myapp://profile or https://example.com/profile."))
        }
        return url.absoluteString
    }
}

public struct Project: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var path: String
    public var lastOpened: Date
    public var deviceID: String?
    public var deviceIsPhysical: Bool?
    public var devicePlatform: String?
    public var sdkPath: String?
    public var launch: LaunchConfiguration
    public var deepLinks: [SavedDeepLink] = []
    private enum CodingKeys: String, CodingKey {
        case id, name, path, lastOpened, deviceID, deviceIsPhysical, devicePlatform, sdkPath, launch, deepLinks
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        path = try values.decode(String.self, forKey: .path)
        lastOpened = try values.decode(Date.self, forKey: .lastOpened)
        deviceID = try values.decodeIfPresent(String.self, forKey: .deviceID)
        deviceIsPhysical = try values.decodeIfPresent(Bool.self, forKey: .deviceIsPhysical)
        devicePlatform = try values.decodeIfPresent(String.self, forKey: .devicePlatform)
        sdkPath = try values.decodeIfPresent(String.self, forKey: .sdkPath)
        launch = try values.decode(LaunchConfiguration.self, forKey: .launch)
        deepLinks = try values.decodeIfPresent([SavedDeepLink].self, forKey: .deepLinks) ?? []
    }
    public init(id: UUID = UUID(), name: String, path: String) {
        self.id = id; self.name = name; self.path = path; lastOpened = Date(); launch = .init()
    }
}

public struct SimulatorDevice: Codable, Identifiable, Equatable {
    public let udid: String
    public let name: String
    public let state: String
    public let isAvailable: Bool
    public var runtime: String?
    public var isPhysical: Bool = false
    public var targetPlatform: String = "ios"
    public var isEmulator: Bool = true
    public var isIOSSimulator: Bool { targetPlatform == "ios" && isEmulator }
    public var id: String { udid }
    public init(udid: String, name: String, state: String, isAvailable: Bool = true, runtime: String? = nil, isPhysical: Bool = false, targetPlatform: String = "ios", isEmulator: Bool? = nil) {
        self.udid = udid; self.name = name; self.state = state; self.isAvailable = isAvailable; self.runtime = runtime; self.isPhysical = isPhysical
        self.targetPlatform = targetPlatform
        self.isEmulator = isEmulator ?? (targetPlatform == "ios" && !isPhysical)
    }
    private enum CodingKeys: String, CodingKey { case udid, name, state, isAvailable, runtime, isPhysical, targetPlatform, isEmulator }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        udid = try values.decode(String.self, forKey: .udid)
        name = try values.decode(String.self, forKey: .name)
        state = try values.decode(String.self, forKey: .state)
        isAvailable = try values.decode(Bool.self, forKey: .isAvailable)
        runtime = try values.decodeIfPresent(String.self, forKey: .runtime)
        isPhysical = try values.decodeIfPresent(Bool.self, forKey: .isPhysical) ?? false
        targetPlatform = try values.decodeIfPresent(String.self, forKey: .targetPlatform) ?? "ios"
        isEmulator = try values.decodeIfPresent(Bool.self, forKey: .isEmulator) ?? (targetPlatform == "ios" && !isPhysical)
    }
    public static func physicalDevices(from data: Data) throws -> [SimulatorDevice] {
        try flutterDevices(from: data).filter { $0.targetPlatform == "ios" && $0.isPhysical }
    }
    public static func flutterDevices(from data: Data) throws -> [SimulatorDevice] {
        struct FlutterDevice: Decodable {
            let id: String, name: String, targetPlatform: String
            let emulator: Bool
            let isSupported: Bool?
            let sdk: String?
        }
        var seen = Set<String>()
        return try JSONDecoder().decode([FlutterDevice].self, from: data)
            .filter { $0.isSupported != false && seen.insert($0.id).inserted }
            .map { SimulatorDevice(udid: $0.id, name: $0.name, state: $0.emulator ? "Booted" : "Available", runtime: $0.sdk,
                                   isPhysical: ["ios", "android"].contains($0.targetPlatform) && !$0.emulator,
                                   targetPlatform: $0.targetPlatform, isEmulator: $0.emulator) }
    }
}

public enum AutomaticDeviceSelection {
    public static func device(from devices: [SimulatorDevice]) -> SimulatorDevice? {
        let simulators = devices.filter { $0.isIOSSimulator && $0.isAvailable }
        return simulators.first { $0.state == "Booted" } ?? simulators.first
    }
}

public enum SessionState: String, Codable {
    case ready, booting, building, running, reloading, restarting, stopping, error, disconnected
    public var isBusy: Bool { [.booting, .building, .reloading, .restarting, .stopping].contains(self) }
    public var title: String {
        switch self {
        case .ready: return L10n.text("Ready")
        case .booting: return L10n.text("Starting simulator")
        case .building: return L10n.text("Building")
        case .running: return L10n.text("Running")
        case .reloading: return "Hot reload"
        case .restarting: return "Hot restart"
        case .stopping: return L10n.text("Stopping")
        case .error: return L10n.text("Error")
        case .disconnected: return L10n.text("Disconnected")
        }
    }
    public var canRestart: Bool { self == .running }
}

public enum SimFlutDockError: LocalizedError {
    case message(String), timeout(String), exited
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .timeout(let action): return L10n.text("Timed out: {0}. See the logs for details.", "\(action)")
        case .exited: return L10n.text("The Flutter process exited. Press Run to start again.")
        }
    }
}

public struct LogEntry: Identifiable {
    public let id = UUID()
    public let date = Date()
    public let text: String
    public let isError: Bool
    public init(_ text: String, isError: Bool = false) { self.text = text; self.isError = isError }
}

public enum SimulatorWindowIdentity {
    /// Window titles are presentation strings. Callers must still require a unique match.
    public static func matches(title: String, device: SimulatorDevice, knownDevices: [SimulatorDevice]) -> Bool {
        guard matches(title: title, device: device) else { return false }
        if title.localizedCaseInsensitiveContains(device.id) { return true }
        let sameName = Set(knownDevices.filter {
            $0.isIOSSimulator && $0.name.caseInsensitiveCompare(device.name) == .orderedSame
        }.map(\.id))
        return sameName == [device.id]
    }
    public static func matches(title: String, device: SimulatorDevice) -> Bool {
        guard device.isIOSSimulator else { return false }
        if title.localizedCaseInsensitiveContains(device.id) { return true }
        let name = NSRegularExpression.escapedPattern(for: device.name)
        let pattern = "^" + name + "(?:$|\\s*[–—(\\-])"
        return title.trimmingCharacters(in: .whitespacesAndNewlines).range(of: pattern, options: .regularExpression) != nil
    }
}

public enum PanelSide: String, CaseIterable {
    case below, above, left, right

    public var isVertical: Bool { self == .left || self == .right }

    public var title: String {
        switch self {
        case .below: return L10n.text("Below")
        case .above: return L10n.text("Above")
        case .left: return L10n.text("Left")
        case .right: return L10n.text("Right")
        }
    }
}

public enum PanelPlacement {
    public static func attachedSize(window: CGRect, visible: CGRect) -> CGSize {
        CGSize(width: max(1, min(window.width, visible.width)), height: 40)
    }
    /// AX uses logical points with a top-left origin on the primary display.
    public static func appKitRect(ax: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: ax.minX, y: primaryTop - ax.maxY, width: ax.width, height: ax.height)
    }
    public static func frame(window: CGRect, size: CGSize, visible: CGRect, offset: CGSize? = nil, side: PanelSide = .below) -> CGRect {
        resolve(window: window, visible: visible, offset: offset, side: side, size: { _ in size }).frame
    }
    /// Resolve each candidate with its own orientation, including screen-edge fallbacks.
    public static func attachedLayout(window: CGRect, horizontalSize: CGSize, verticalSize: CGSize, visible: CGRect, side: PanelSide) -> (frame: CGRect, side: PanelSide) {
        resolve(window: window, visible: visible, offset: nil, side: side) {
            $0.isVertical ? verticalSize : horizontalSize
        }
    }
    private static func resolve(window: CGRect, visible: CGRect, offset: CGSize?, side: PanelSide, size: (PanelSide) -> CGSize) -> (frame: CGRect, side: PanelSide) {
        let gap: CGFloat = 8
        func candidate(_ side: PanelSide) -> CGRect {
            let size = size(side)
            let origin: CGPoint
            switch side {
            case .below, .above:
                // Collapse the optional gap at the screen edge before switching
                // sides. The panel itself must still fit outside the simulator.
                let availableGap = side == .below
                    ? window.minY - visible.minY - size.height
                    : visible.maxY - window.maxY - size.height
                let verticalGap = min(gap, max(0, availableGap))
                origin = CGPoint(x: max(visible.minX, min(window.midX - size.width / 2, visible.maxX - size.width)),
                                 y: side == .below ? window.minY - size.height - verticalGap : window.maxY + verticalGap)
            case .left, .right:
                origin = CGPoint(x: side == .left ? window.minX - size.width - gap : window.maxX + gap,
                                 y: max(visible.minY, min(window.maxY - size.height, visible.maxY - size.height)))
            }
            return CGRect(origin: origin, size: size)
        }
        let size = size(side)
        var origin = candidate(side).origin
        if let offset {
            origin = CGPoint(x: window.minX + offset.width, y: window.minY + offset.height)
        } else {
            let fallback: [PanelSide]
            switch side {
            case .below: fallback = [.above, .right, .left]
            case .above: fallback = [.below, .right, .left]
            case .left: fallback = [.right, .below, .above]
            case .right: fallback = [.left, .below, .above]
            }
            for candidateSide in [side] + fallback {
                let frame = candidate(candidateSide)
                if visible.contains(frame) { return (frame, candidateSide) }
            }
        }
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        return (CGRect(origin: origin, size: size), side)
    }
}

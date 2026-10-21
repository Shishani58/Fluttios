import XCTest

@testable import SimFlutDockCore

final class LaunchModeTests: XCTestCase {
    func testProjectDefaultsRemoveHiddenAdvancedParameters() throws {
        var launch = LaunchConfiguration()
        launch.scheme = "dev"
        launch.entrypoint = "lib/dev.dart"
        launch.arguments = ["--dart-define=OLD=true"]
        launch.setMode(.release)
        let defaults = launch.usingProjectDefaults()
        XCTAssertEqual(defaults.mode, .release)
        XCTAssertEqual(defaults.buildConfiguration, "Release")
        XCTAssertEqual(
            try defaults.validatedArguments(for: phone), ["run", "--machine", "--release", "--target", "lib/main.dart"])
    }
    func testOtherFlutterTargetsAreDiscoveredAndPreserved() throws {
        let json = Data(
            #"[{"id":"ANDROID","name":"Pixel","targetPlatform":"android","emulator":false},{"id":"MAC","name":"Mac","targetPlatform":"darwin","emulator":false},{"id":"WEB","name":"Chrome","targetPlatform":"web-javascript","emulator":false},{"id":"SIM","name":"iPhone","targetPlatform":"ios","emulator":true},{"id":"ANDROID","name":"Pixel","targetPlatform":"android","emulator":false},{"id":"NO","name":"Unsupported","targetPlatform":"android","emulator":false,"isSupported":false}]"#
                .utf8)
        let devices = try SimulatorDevice.flutterDevices(from: json)
        XCTAssertEqual(devices.map(\.id), ["ANDROID", "MAC", "WEB", "SIM"])
        for device in devices.prefix(3) {
            XCTAssertFalse(device.isIOSSimulator)
            XCTAssertTrue(LaunchMode.profile.supports(device))
            XCTAssertTrue(LaunchMode.release.supports(device))
            XCTAssertEqual(try JSONDecoder().decode(SimulatorDevice.self, from: JSONEncoder().encode(device)), device)
        }
        XCTAssertTrue(devices[3].isIOSSimulator)
        XCTAssertFalse(LaunchMode.release.supports(devices[3]))
    }
    private let simulator = SimulatorDevice(udid: "SIM", name: "iPhone", state: "Booted")
    private let phone = SimulatorDevice(udid: "PHONE", name: "iPhone", state: "Подключено", isPhysical: true)
    func testModesAndFlavorConfigurationsMatchTarget() throws {
        var launch = LaunchConfiguration()
        launch.scheme = "dev"
        launch.buildConfiguration = "Debug-dev"
        for mode in LaunchMode.allCases {
            launch.setMode(mode)
            XCTAssertEqual(launch.buildConfiguration, mode.title + "-dev")
            XCTAssertEqual(
                try launch.validatedArguments(for: phone),
                ["run", "--machine", "--" + mode.rawValue, "--target", "lib/main.dart", "--flavor", "dev"])
            if mode == .debug {
                XCTAssertNoThrow(try launch.validatedArguments(for: simulator))
            } else {
                XCTAssertThrowsError(try launch.validatedArguments(for: simulator))
            }
            let restored = try JSONDecoder().decode(LaunchConfiguration.self, from: JSONEncoder().encode(launch))
            XCTAssertEqual(restored, launch)
        }
        launch.buildConfiguration = "Debug-dev"
        XCTAssertThrowsError(try launch.validatedArguments(for: phone))
    }
    func testExistingLaunchSettingsDecodeAsDebug() throws {
        let data = Data(
            #"{"entrypoint":"lib/dev.dart","arguments":["--dart-define=NAME=А Б"],"scheme":"dev","buildConfiguration":"Debug-dev"}"#
                .utf8)
        let launch = try JSONDecoder().decode(LaunchConfiguration.self, from: data)
        XCTAssertEqual(launch.mode, .debug)
        XCTAssertEqual(launch.entrypoint, "lib/dev.dart")
        XCTAssertEqual(launch.arguments, ["--dart-define=NAME=А Б"])
        XCTAssertNoThrow(try launch.validatedArguments(for: simulator))
    }
    func testPhysicalTargetPersistsAndOlderProjectsRemainReadable() throws {
        var project = Project(name: "Physical", path: "/tmp")
        project.deviceID = phone.id
        project.deviceIsPhysical = true
        project.launch.setMode(.profile)
        let encoded = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: encoded), project)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "deviceIsPhysical")
        var launch = try XCTUnwrap(json["launch"] as? [String: Any])
        launch.removeValue(forKey: "mode")
        launch["buildConfiguration"] = "Debug"
        json["launch"] = launch
        let restored = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.deviceIsPhysical)
        XCTAssertEqual(restored.launch.mode, .debug)
        XCTAssertEqual(restored.deviceID, phone.id)
    }
    func testSimctlAndPhysicalDeviceDiscovery() throws {
        let simctl = Data(#"{"udid":"SIM","name":"iPhone","state":"Booted","isAvailable":true}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(SimulatorDevice.self, from: simctl).isPhysical)
        let flutter = Data(
            #"[{"id":"PHONE","name":"iPhone","targetPlatform":"ios","emulator":false,"isSupported":true,"sdk":"iOS 26"},{"id":"PHONE","name":"iPhone","targetPlatform":"ios","emulator":false},{"id":"SIM","name":"iPhone","targetPlatform":"ios","emulator":true},{"id":"MAC","name":"Mac","targetPlatform":"darwin","emulator":false},{"id":"UNSUPPORTED","name":"iPad","targetPlatform":"ios","emulator":false,"isSupported":false}]"#
                .utf8)
        let devices = try SimulatorDevice.physicalDevices(from: flutter)
        XCTAssertEqual(devices.map(\.id), ["PHONE"])
        XCTAssertTrue(devices[0].isPhysical)
        XCTAssertEqual(devices[0].runtime, "iOS 26")
        XCTAssertFalse(SimulatorWindowIdentity.matches(title: "iPhone – iOS 26", device: devices[0]))
    }
    @MainActor func testPhysicalDeviceDoesNotBootSimulator() async throws {
        try await SimulatorService().boot(phone)
    }
    @MainActor func testOtherTargetsDoNotUseIOSBootOrXcodeSettings() async throws {
        let service = SimulatorService()
        let project = Project(name: "Other target", path: "/tmp/fluttios-target-without-ios")
        for platform in ["android", "darwin", "web-javascript"] {
            let device = SimulatorDevice(
                udid: platform, name: platform, state: "Доступно", targetPlatform: platform, isEmulator: false)
            try await service.boot(device)
            let identifier = try await service.bundleIdentifier(project, device: device)
            XCTAssertEqual(identifier, URL(fileURLWithPath: project.path).resolvingSymlinksInPath().path)
        }
    }
}

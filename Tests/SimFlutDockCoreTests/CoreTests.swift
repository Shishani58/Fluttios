import XCTest
@testable import SimFlutDockCore

final class DartMemoryTests: XCTestCase {
    func testHeapUsageDoesNotIncludeCapacityOrExternalMemory() {
        XCTAssertEqual(DartConsole.heapBytes(from: ["result": ["type": "MemoryUsage", "heapUsage": 1024, "heapCapacity": 4096, "externalUsage": 2048]]), 1024)
        XCTAssertEqual(DartConsole.heapBytes(from: ["result": ["type": "MemoryUsage", "heapUsage": 0]]), 0)
    }

    func testMissingCollectedAndInvalidSamplesStayUnavailable() {
        for response: [String: Any] in [
            [:], ["result": ["type": "Sentinel", "kind": "Collected"]],
            ["result": ["type": "MemoryUsage", "heapUsage": -1]],
            ["result": ["type": "MemoryUsage", "heapUsage": true]],
            ["result": ["type": "MemoryUsage", "heapUsage": 1.5]]
        ] {
            XCTAssertNil(DartConsole.heapBytes(from: response))
        }
    }

    @MainActor func testInactiveSessionHasNoMemorySample() async {
        let session = FlutterSession(projectID: UUID())
        let bytes = await session.mainIsolateHeapBytes()
        XCTAssertNil(bytes)
        XCTAssertEqual(session.state, .ready)
    }
}

final class LaunchModeTests: XCTestCase {
    func testProjectDefaultsRemoveHiddenAdvancedParameters() throws {
        var launch = LaunchConfiguration()
        launch.scheme = "dev"; launch.entrypoint = "lib/dev.dart"
        launch.arguments = ["--dart-define=OLD=true"]
        launch.setMode(.release)
        let defaults = launch.usingProjectDefaults()
        XCTAssertEqual(defaults.mode, .release)
        XCTAssertEqual(defaults.buildConfiguration, "Release")
        XCTAssertEqual(try defaults.validatedArguments(for: phone), ["run", "--machine", "--release", "--target", "lib/main.dart"])
    }
    func testOtherFlutterTargetsAreDiscoveredAndPreserved() throws {
        let json = Data(#"[{"id":"ANDROID","name":"Pixel","targetPlatform":"android","emulator":false},{"id":"MAC","name":"Mac","targetPlatform":"darwin","emulator":false},{"id":"WEB","name":"Chrome","targetPlatform":"web-javascript","emulator":false},{"id":"SIM","name":"iPhone","targetPlatform":"ios","emulator":true},{"id":"ANDROID","name":"Pixel","targetPlatform":"android","emulator":false},{"id":"NO","name":"Unsupported","targetPlatform":"android","emulator":false,"isSupported":false}]"#.utf8)
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
        launch.scheme = "dev"; launch.buildConfiguration = "Debug-dev"
        for mode in LaunchMode.allCases {
            launch.setMode(mode)
            XCTAssertEqual(launch.buildConfiguration, mode.title + "-dev")
            XCTAssertEqual(try launch.validatedArguments(for: phone), ["run", "--machine", "--" + mode.rawValue, "--target", "lib/main.dart", "--flavor", "dev"])
            if mode == .debug { XCTAssertNoThrow(try launch.validatedArguments(for: simulator)) }
            else { XCTAssertThrowsError(try launch.validatedArguments(for: simulator)) }
            let restored = try JSONDecoder().decode(LaunchConfiguration.self, from: JSONEncoder().encode(launch))
            XCTAssertEqual(restored, launch)
        }
        launch.buildConfiguration = "Debug-dev"
        XCTAssertThrowsError(try launch.validatedArguments(for: phone))
    }
    func testExistingLaunchSettingsDecodeAsDebug() throws {
        let data = Data(#"{"entrypoint":"lib/dev.dart","arguments":["--dart-define=NAME=А Б"],"scheme":"dev","buildConfiguration":"Debug-dev"}"#.utf8)
        let launch = try JSONDecoder().decode(LaunchConfiguration.self, from: data)
        XCTAssertEqual(launch.mode, .debug)
        XCTAssertEqual(launch.entrypoint, "lib/dev.dart")
        XCTAssertEqual(launch.arguments, ["--dart-define=NAME=А Б"])
        XCTAssertNoThrow(try launch.validatedArguments(for: simulator))
    }
    func testPhysicalTargetPersistsAndOlderProjectsRemainReadable() throws {
        var project = Project(name: "Physical", path: "/tmp")
        project.deviceID = phone.id; project.deviceIsPhysical = true; project.launch.setMode(.profile)
        let encoded = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: encoded), project)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "deviceIsPhysical")
        var launch = try XCTUnwrap(json["launch"] as? [String: Any])
        launch.removeValue(forKey: "mode"); launch["buildConfiguration"] = "Debug"
        json["launch"] = launch
        let restored = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.deviceIsPhysical)
        XCTAssertEqual(restored.launch.mode, .debug)
        XCTAssertEqual(restored.deviceID, phone.id)
    }
    func testSimctlAndPhysicalDeviceDiscovery() throws {
        let simctl = Data(#"{"udid":"SIM","name":"iPhone","state":"Booted","isAvailable":true}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(SimulatorDevice.self, from: simctl).isPhysical)
        let flutter = Data(#"[{"id":"PHONE","name":"iPhone","targetPlatform":"ios","emulator":false,"isSupported":true,"sdk":"iOS 26"},{"id":"PHONE","name":"iPhone","targetPlatform":"ios","emulator":false},{"id":"SIM","name":"iPhone","targetPlatform":"ios","emulator":true},{"id":"MAC","name":"Mac","targetPlatform":"darwin","emulator":false},{"id":"UNSUPPORTED","name":"iPad","targetPlatform":"ios","emulator":false,"isSupported":false}]"#.utf8)
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
            let device = SimulatorDevice(udid: platform, name: platform, state: "Доступно", targetPlatform: platform, isEmulator: false)
            try await service.boot(device)
            let identifier = try await service.bundleIdentifier(project, device: device)
            XCTAssertEqual(identifier, URL(fileURLWithPath: project.path).resolvingSymlinksInPath().path)
        }
    }
}

final class ParserTests: XCTestCase {
    func testFragmentedUTF8AndMultipleMessages() throws {
        var parser = MachineParser()
        let source = Data("[{\"event\":\"app.log\",\"params\":{\"log\":\"Привет\"}}]\n[{\"id\":3,\"result\":true},{\"event\":\"app.started\"}]\n".utf8)
        var output: [MachineOutput] = []
        for byte in source { output += parser.feed(Data([byte])) }
        XCTAssertEqual(output.count, 3)
        guard case .message(let message) = output[0] else { return XCTFail() }
        XCTAssertEqual((message["params"] as? [String: Any])?["log"] as? String, "Привет")
    }
    func testOrdinaryTextMalformedJSONAndFinalLine() {
        var parser = MachineParser()
        let output = parser.feed(Data("building\n[not json]\n[1,2]\n[{\"event\":\"app.stop\"}]\nlast".utf8)) + parser.finish()
        XCTAssertEqual(output.count, 5)
        guard case .text(let last) = output.last else { return XCTFail() }
        XCTAssertEqual(last, "last")
        XCTAssertTrue(parser.finish().isEmpty)
    }
    func testDartConsoleJSONRemainsOrdinaryText() {
        var parser = MachineParser(parseMessages: false)
        let output = parser.feed(Data("[{\"event\":\"app.stop\"}]\n".utf8))
        guard case .text(let text) = output.first else { return XCTFail() }
        XCTAssertEqual(text, "[{\"event\":\"app.stop\"}]")
    }
    func testUnboundedLineIsCapped() {
        var parser = MachineParser()
        XCTAssertEqual(parser.feed(Data(repeating: 65, count: 1_048_577)).count, 1)
    }
}

final class WindowIdentityTests: XCTestCase {
    private let device = SimulatorDevice(udid: "AABB-1234", name: "Demo iPhone 17 Pro", state: "Booted")
    func testClassicAndDeviceHubTitles() {
        for title in [device.name, device.name + " – iOS 26.5", device.name + " — iOS 26.5", device.name + " (26.5)", "  " + device.name + " - iOS 26.5  ", "Simulator aabb-1234"] {
            XCTAssertTrue(SimulatorWindowIdentity.matches(title: title, device: device), title)
        }
    }
    func testDuplicateDeviceNameRequiresManualBindingEvenWithOneWindow() {
        let duplicate = SimulatorDevice(udid: "OTHER", name: device.name, state: "Shutdown")
        let title = device.name + " – iOS 26.5"
        XCTAssertFalse(SimulatorWindowIdentity.matches(title: title, device: device, knownDevices: [device, duplicate]))
        XCTAssertFalse(SimulatorWindowIdentity.matches(title: title, device: duplicate, knownDevices: [device, duplicate]))
        XCTAssertTrue(SimulatorWindowIdentity.matches(title: "Simulator " + device.id, device: device, knownDevices: [device, duplicate]))
        XCTAssertTrue(SimulatorWindowIdentity.matches(title: title, device: device, knownDevices: [device]))
    }
    func testDoesNotBindToAnotherDeviceOrManagementWindow() {
        for title in ["iPhone 17 Pro – iOS 26.5", device.name + " Max – iOS 26.5", "Device Hub", "Devices and Simulators"] {
            XCTAssertFalse(SimulatorWindowIdentity.matches(title: title, device: device), title)
        }
    }
    func testDuplicateNamesStayAmbiguousAndRegexCharactersAreLiteral() {
        let duplicate = SimulatorDevice(udid: "OTHER", name: device.name, state: "Booted")
        let title = device.name + " – iOS 26.5"
        XCTAssertTrue(SimulatorWindowIdentity.matches(title: title, device: device))
        XCTAssertTrue(SimulatorWindowIdentity.matches(title: title, device: duplicate))
        let special = SimulatorDevice(udid: "SPECIAL", name: "Test (A)+", state: "Booted")
        XCTAssertTrue(SimulatorWindowIdentity.matches(title: "Test (A)+ – iOS 26.5", device: special))
        XCTAssertFalse(SimulatorWindowIdentity.matches(title: "Test A – iOS 26.5", device: special))
    }
}

final class PlacementTests: XCTestCase {
    func testPreferredAboveReturnsAsSoonAsSpaceBecomesAvailable() {
        let visible = CGRect(x: 0, y: 0, width: 1496, height: 939)
        for height: CGFloat in [40, 62] {
            let size = CGSize(width: 422, height: height)
            let lastFittingY = visible.maxY - 704 - height
            for y in [39, 100, lastFittingY, lastFittingY + 1, 200, lastFittingY + 1, lastFittingY, 100, 39] {
                let window = CGRect(x: 648, y: y, width: 422, height: 704)
                let panel = PanelPlacement.frame(window: window, size: size, visible: visible, side: .above)
                if y <= lastFittingY {
                    XCTAssertGreaterThanOrEqual(panel.minY, window.maxY)
                } else {
                    XCTAssertEqual(panel.maxY, window.minY - 8)
                }
                XCTAssertTrue(visible.contains(panel))
            }
        }
    }

    func testExplicitBelowReturnsAsSoonAsSpaceBecomesAvailable() {
        let visible = CGRect(x: 0, y: 0, width: 1496, height: 939)
        let size = CGSize(width: 422, height: 40)
        for y: CGFloat in [100, 40, 39, 40, 45, 100] {
            let window = CGRect(x: 648, y: y, width: 422, height: 704)
            let panel = PanelPlacement.frame(window: window, size: size, visible: visible, side: .below)
            if y >= size.height { XCTAssertLessThanOrEqual(panel.maxY, window.minY) }
            else { XCTAssertEqual(panel.minY, window.maxY + 8) }
            XCTAssertTrue(visible.contains(panel))
        }
    }
    func testAbovePanelUsesRemainingGapBeforeSwitchingBelow() {
        let visible = CGRect(x: -1440, y: 40, width: 1440, height: 835)
        for height: CGFloat in [40, 62] {
            let size = CGSize(width: 422, height: height)
            for remainingGap: CGFloat in [8, 6, 1, 0] {
                let window = CGRect(x: -900, y: visible.maxY - height - remainingGap - 300, width: 422, height: 300)
                let panel = PanelPlacement.frame(window: window, size: size, visible: visible, side: .above)
                XCTAssertEqual(panel.minY, window.maxY + remainingGap)
                XCTAssertEqual(panel.maxY, visible.maxY)
                XCTAssertTrue(visible.contains(panel))
                XCTAssertGreaterThanOrEqual(panel.minY, window.maxY)
            }
            let window = CGRect(x: -900, y: visible.maxY - height + 1 - 300, width: 422, height: 300)
            let panel = PanelPlacement.frame(window: window, size: size, visible: visible, side: .above)
            XCTAssertEqual(panel.maxY, window.minY - 8)
            XCTAssertTrue(visible.contains(panel))
        }
    }
    func testBelowPanelUsesRemainingGapAtBottomEdge() {
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 835)
        let window = CGRect(x: 500, y: 84, width: 422, height: 300)
        let panel = PanelPlacement.frame(window: window, size: CGSize(width: 422, height: 40), visible: visible)
        XCTAssertEqual(panel.minY, visible.minY)
        XCTAssertEqual(panel.maxY, window.minY - 4)
    }
    func testPanelFollowsCurrentHeightAfterSimulatorShrinks() {
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 835)
        let original = PanelPlacement.appKitRect(ax: CGRect(x: 500, y: 200, width: 422, height: 600), primaryTop: 900)
        let resized = PanelPlacement.appKitRect(ax: CGRect(x: 500, y: 200, width: 422, height: 300), primaryTop: 900)
        let originalPanel = PanelPlacement.frame(window: original, size: PanelPlacement.attachedSize(window: original, visible: visible), visible: visible)
        let resizedPanel = PanelPlacement.frame(window: resized, size: PanelPlacement.attachedSize(window: resized, visible: visible), visible: visible)
        XCTAssertEqual(originalPanel.minY, 52)
        XCTAssertEqual(resizedPanel.minY, 352)
        XCTAssertEqual(resizedPanel.height, 40)
        XCTAssertTrue(visible.contains(resizedPanel))
        XCTAssertFalse(resized.intersects(resizedPanel))

        // Moving the smaller window to the menu-bar boundary must preserve
        // its current height and the gap below its bottom edge.
        let moved = PanelPlacement.appKitRect(ax: CGRect(x: 500, y: 25, width: 422, height: 300), primaryTop: 900)
        let movedPanel = PanelPlacement.frame(window: moved, size: resizedPanel.size, visible: visible)
        XCTAssertEqual(movedPanel.minY, 527)
        XCTAssertEqual(movedPanel.maxY, moved.minY - 8)
        XCTAssertTrue(visible.contains(movedPanel))
    }
    func testAttachedPanelMatchesWindowWidthAndRemainsOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 1000)
        for width: CGFloat in [260, 422, 850, 1600] {
            let window = CGRect(x: 0, y: 150, width: width, height: 600)
            let size = PanelPlacement.attachedSize(window: window, visible: visible)
            XCTAssertEqual(size.width, min(width, visible.width))
            let frame = PanelPlacement.frame(window: window, size: size, visible: visible)
            XCTAssertTrue(visible.contains(frame))
            XCTAssertLessThanOrEqual(frame.width, window.width)
        }
    }
    func testRequestedSideKeepsPanelOutsideSimulator() {
        let visible = CGRect(x: 0, y: 0, width: 1800, height: 1200)
        let window = CGRect(x: 700, y: 300, width: 400, height: 600)
        let size = CGSize(width: 360, height: 40)
        for side in PanelSide.allCases {
            let frame = PanelPlacement.frame(window: window, size: size, visible: visible, side: side)
            XCTAssertTrue(visible.contains(frame))
            XCTAssertFalse(window.intersects(frame))
            switch side {
            case .below: XCTAssertEqual(frame.maxY, window.minY - 8)
            case .above: XCTAssertEqual(frame.minY, window.maxY + 8)
            case .left: XCTAssertEqual(frame.maxX, window.minX - 8)
            case .right: XCTAssertEqual(frame.minX, window.maxX + 8)
            }
        }
    }
    func testSideFallsBackAcrossWindowAtMonitorEdge() {
        let visible = CGRect(x: -1440, y: 40, width: 1440, height: 860)
        let size = CGSize(width: 360, height: 40)
        let leftWindow = CGRect(x: -1420, y: 100, width: 400, height: 600)
        let right = PanelPlacement.frame(window: leftWindow, size: size, visible: visible, side: .left)
        XCTAssertEqual(right.minX, leftWindow.maxX + 8)
        XCTAssertTrue(visible.contains(right))
        let rightWindow = CGRect(x: -420, y: 100, width: 400, height: 600)
        let left = PanelPlacement.frame(window: rightWindow, size: size, visible: visible, side: .right)
        XCTAssertEqual(left.maxX, rightWindow.minX - 8)
        XCTAssertTrue(visible.contains(left))
        let topWindow = CGRect(x: -900, y: 280, width: 400, height: 600)
        let below = PanelPlacement.frame(window: topWindow, size: size, visible: visible, side: .above)
        XCTAssertEqual(below.maxY, topWindow.minY - 8)
        XCTAssertTrue(visible.contains(below))
    }
    func testFallbackWhenNeitherHorizontalSideFits() {
        let visible = CGRect(x: 0, y: 0, width: 700, height: 900)
        let window = CGRect(x: 150, y: 200, width: 400, height: 600)
        let frame = PanelPlacement.frame(window: window, size: CGSize(width: 360, height: 40), visible: visible, side: .right)
        XCTAssertEqual(frame.maxY, window.minY - 8)
        XCTAssertTrue(visible.contains(frame))
        XCTAssertFalse(window.intersects(frame))
    }
    func testAttachedLayoutUsesVerticalColumnOnEitherSide() {
        let visible = CGRect(x: -1440, y: 40, width: 1440, height: 860)
        let window = CGRect(x: -900, y: 100, width: 400, height: 600)
        for side in [PanelSide.left, .right] {
            let layout = PanelPlacement.attachedLayout(window: window, horizontalSize: CGSize(width: 400, height: 70),
                                                       verticalSize: CGSize(width: 50, height: 374), visible: visible, side: side)
            XCTAssertEqual(layout.side, side)
            XCTAssertEqual(layout.frame.size, CGSize(width: 50, height: 374))
            XCTAssertEqual(layout.frame.maxY, window.maxY)
            XCTAssertTrue(visible.contains(layout.frame))
            XCTAssertFalse(window.intersects(layout.frame))
        }
    }
    func testAttachedFallbackChangesOrientationAndReturnsToPreferredSide() {
        let visible = CGRect(x: 0, y: 0, width: 500, height: 900)
        let horizontal = CGSize(width: 400, height: 70)
        let vertical = CGSize(width: 50, height: 374)
        let crowded = CGRect(x: 50, y: 200, width: 400, height: 600)
        let fallback = PanelPlacement.attachedLayout(window: crowded, horizontalSize: horizontal, verticalSize: vertical, visible: visible, side: .right)
        XCTAssertEqual(fallback.side, .below)
        XCTAssertEqual(fallback.frame.size, horizontal)
        XCTAssertFalse(crowded.intersects(fallback.frame))
        let moved = CGRect(x: 10, y: 200, width: 400, height: 600)
        let restored = PanelPlacement.attachedLayout(window: moved, horizontalSize: horizontal, verticalSize: vertical, visible: visible, side: .right)
        XCTAssertEqual(restored.side, .right)
        XCTAssertEqual(restored.frame.size, vertical)
        let tall = CGRect(x: 10, y: 50, width: 400, height: 840)
        let sideFallback = PanelPlacement.attachedLayout(window: tall, horizontalSize: horizontal, verticalSize: vertical, visible: visible, side: .above)
        XCTAssertEqual(sideFallback.side, .right)
        XCTAssertEqual(sideFallback.frame.size, vertical)
        XCTAssertTrue(visible.contains(sideFallback.frame))
    }
    func testAXConversionWithDisplayAbovePrimary() {
        let rect = PanelPlacement.appKitRect(ax: CGRect(x: -1000, y: -700, width: 400, height: 600), primaryTop: 900)
        XCTAssertEqual(rect.minY, 1000); XCTAssertEqual(rect.minX, -1000)
    }
    func testBelowAndAboveFallback() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900), size = CGSize(width: 570, height: 80)
        let below = PanelPlacement.frame(window: CGRect(x: 500, y: 200, width: 400, height: 600), size: size, visible: visible)
        XCTAssertEqual(below.minY, 112)
        let above = PanelPlacement.frame(window: CGRect(x: 500, y: 20, width: 400, height: 600), size: size, visible: visible)
        XCTAssertEqual(above.minY, 628); XCTAssertTrue(visible.contains(above))
    }
    func testOffsetClampedOnNegativeMonitor() {
        let visible = CGRect(x: -1440, y: 40, width: 1440, height: 860)
        let frame = PanelPlacement.frame(window: CGRect(x: -400, y: 50, width: 350, height: 700), size: CGSize(width: 570, height: 80), visible: visible, offset: CGSize(width: 900, height: -300))
        XCTAssertTrue(visible.contains(frame)); XCTAssertEqual(frame.maxX, 0); XCTAssertEqual(frame.minY, 40)
    }
}

final class StoreTests: XCTestCase {
    @MainActor func testClearingSavedProjectsPersistsEmptyListAndPreservesFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let projectFolders = [folder.appendingPathComponent("A"), folder.appendingPathComponent("B")]
        for url in projectFolders {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try "name: counter\ndependencies:\n  flutter:\n    sdk: flutter\n".write(to: url.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
            try "source stays intact".write(to: url.appendingPathComponent("main.dart"), atomically: true, encoding: .utf8)
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
        let a = folder.appendingPathComponent("проект A"), b = folder.appendingPathComponent("проект B")
        for url in [a, b] {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("ios"), withIntermediateDirectories: true)
            try "name: counter\ndependencies:\n  flutter:\n    sdk: flutter\n".write(to: url.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        }
        let archive = folder.appendingPathComponent("projects.json")
        let store = ProjectStore(file: archive)
        var first = try store.open(a); first.deviceID = "device-A"; first.sdkPath = "/SDK with spaces"; first.launch.arguments = ["--dart-define=NAME=А Б"]; store.update(first)
        XCTAssertEqual(try store.open(a).id, first.id); XCTAssertEqual(store.projects.count, 1)
        let second = try store.open(b)
        store.select(first.id)
        let reopened = ProjectStore(file: archive)
        XCTAssertEqual(reopened.selectedID, first.id); XCTAssertEqual(reopened.selected?.sdkPath, first.sdkPath)
        XCTAssertEqual(reopened.selected?.launch.arguments, first.launch.arguments)
        XCTAssertNotEqual(reopened.label(first), reopened.label(second))
        reopened.remove(second.id); XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        try FileManager.default.removeItem(at: a)
        let relocated = try reopened.open(b, replacing: first.id)
        XCTAssertEqual(relocated.id, first.id); XCTAssertEqual(relocated.path, b.path)
    }
    @MainActor func testCorruptStoreDoesNotOverwriteEvidence() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("invalid".utf8).write(to: file)
        let store = ProjectStore(file: file)
        XCTAssertNotNil(store.persistenceError); store.selectedID = UUID()
        XCTAssertEqual(try String(contentsOf: file), "invalid")
        let backup = try XCTUnwrap(store.recoverPersistence())
        defer { try? FileManager.default.removeItem(at: backup) }
        XCTAssertEqual(try String(contentsOf: backup), "invalid")
        XCTAssertNil(ProjectStore(file: file).persistenceError)
    }
    func testRejectsNonFlutterFolder() { XCTAssertThrowsError(try ProjectStore.validate(URL(fileURLWithPath: "/tmp"))) }
    func testReservedArgumentsAndDebugConfiguration() throws {
        var config = LaunchConfiguration(); config.arguments = ["--dart-define=TEXT=Привет мир"]
        XCTAssertTrue(try config.validatedArguments().contains("--dart-define=TEXT=Привет мир"))
        for arg in ["--debug", "--profile", "--release", "-dother", "--target=x", "--flavor", "--no-resident", "--"] {
            config.arguments = [arg]; XCTAssertThrowsError(try config.validatedArguments())
        }
        config.arguments = []
        for name in ["Release", "Profile", "Debugging"] {
            config.buildConfiguration = name; XCTAssertThrowsError(try config.validatedArguments())
        }
        config.buildConfiguration = "Debug-dev"; config.scheme = "dev"
        XCTAssertEqual(try config.validatedArguments(), ["run", "--machine", "--debug", "--target", "lib/main.dart", "--flavor", "dev"])
    }
}

final class ClientTests: XCTestCase {
    @MainActor func testResponseRoutingErrorsAndUniqueIDs() async throws {
        var writes: [[String: Any]] = []
        let client = MachineClient { data in writes += try JSONSerialization.jsonObject(with: data) as! [[String: Any]] }
        let a = Task { try await client.request("app.restart", params: [:]) }
        let b = Task { try await client.request("app.stop", params: [:]) }
        while writes.count < 2 { await Task.yield() }
        let first = writes[0]["id"] as! Int, second = writes[1]["id"] as! Int
        XCTAssertNotEqual(first, second)
        client.receive(["id": second, "error": "failure"])
        client.receive(["id": first, "result": true])
        let response = try await a.value
        XCTAssertEqual(response["result"] as? Bool, true)
        do { _ = try await b.value; XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("failure")) }
        XCTAssertEqual(client.pendingCount, 0)
    }
    @MainActor func testTimeoutTerminationAndCancellationCleanPendingRequests() async throws {
        let client = MachineClient { _ in }
        do { _ = try await client.request("timeout", params: [:], timeout: 0.01); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("timeout")) }
        XCTAssertEqual(client.pendingCount, 0)
        let pending = Task { try await client.request("close", params: [:]) }
        while client.pendingCount == 0 { await Task.yield() }
        client.close()
        do { _ = try await pending.value; XCTFail() } catch {}
        XCTAssertEqual(client.pendingCount, 0)
        let cancel = Task { try await client.request("cancel", params: [:]) }
        while client.pendingCount == 0 { await Task.yield() }
        cancel.cancel()
        do { _ = try await cancel.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(client.pendingCount, 0)
    }
    @MainActor func testVMServiceUsesUnwrappedRequests() async throws {
        var request: [String: Any]?
        let client = MachineClient(arrayWrapped: false) { data in request = try JSONSerialization.jsonObject(with: data) as? [String: Any] }
        let task = Task { try await client.request("getVM", params: [:]) }
        while request == nil { await Task.yield() }
        XCTAssertEqual(request?["method"] as? String, "getVM")
        client.receive(["id": request!["id"]!, "result": ["type": "VM"]])
        let response = try await task.value
        XCTAssertEqual((response["result"] as? [String: Any])?["type"] as? String, "VM")
    }
    @MainActor func testWriteFailure() async {
        let client = MachineClient { _ in throw SimFlutDockError.exited }
        do { _ = try await client.request("write", params: [:]); XCTFail() } catch {}
        XCTAssertEqual(client.pendingCount, 0)
    }
}

final class SessionTests: XCTestCase {
    @MainActor func testProgressTracksNestedOperationsAndIgnoresOtherApps() {
        let session = FlutterSession(projectID: UUID())
        session.prepare(project: Project(name: "A", path: "/tmp"), device: SimulatorDevice(udid: "SIM", name: "iPhone", state: "Booted"))
        session.setPreparationStage("Проверка Flutter SDK")
        XCTAssertEqual(session.progressMessage, "Проверка Flutter SDK")
        session.handle(.message(["event": "app.start", "params": ["appId": "owned"]]))
        func progress(_ id: String, message: String? = nil, finished: Bool = false, app: String = "owned") {
            var params: [String: Any] = ["appId": app, "id": id, "finished": finished]
            if let message { params["message"] = message }
            session.handle(.message(["event": "app.progress", "params": params]))
        }
        progress("xcode", message: "Running Xcode build...")
        XCTAssertEqual(session.progressMessage, L10n.text("Building in Xcode"))
        progress("install", message: "Installing and launching...")
        XCTAssertEqual(session.progressMessage, L10n.text("Installing and launching"))
        progress("other", message: "Other app", app: "foreign")
        progress("missing", finished: true)
        progress("xcode", finished: true)
        XCTAssertEqual(session.progressMessage, L10n.text("Installing and launching"))
        progress("install", finished: true)
        XCTAssertEqual(session.progressMessage, "Проверка Flutter SDK")
        XCTAssertTrue(session.logs.contains { $0.text == "Running Xcode build..." })
        session.stop()
        progress("late", message: "Late build event")
        XCTAssertEqual(session.progressMessage, L10n.text("Stopping app"))
        session.launchFailed(CancellationError())
        XCTAssertNil(session.progressMessage)
        XCTAssertEqual(session.state, .ready)
        session.prepare(project: Project(name: "B", path: "/tmp"), device: SimulatorDevice(udid: "SIM", name: "iPhone", state: "Booted"))
        session.launchFailed(SimFlutDockError.message("Build failed"))
        XCTAssertNil(session.progressMessage)
    }
    @MainActor func testProgressClearsOnStartupAndProcessExit() async throws {
        let session = FlutterSession(projectID: UUID())
        try session.start(executable: "/usr/bin/true", project: Project(name: "A", path: "/tmp"), device: SimulatorDevice(udid: "SIM", name: "iPhone", state: "Booted"), bundleID: "com.test.progress", captureDartConsole: false)
        XCTAssertNotNil(session.progressMessage)
        session.handle(.message(["event": "app.progress", "params": ["id": "build", "message": "Running Xcode build..."]]))
        session.handle(.message(["event": "app.started", "params": [:]]))
        XCTAssertEqual(session.state, .running)
        XCTAssertNil(session.progressMessage)
        session.handle(.message(["event": "app.progress", "params": ["id": "late", "message": "Late build event"]]))
        XCTAssertNil(session.progressMessage)
        try await wait { !session.isAlive }
        XCTAssertNil(session.progressMessage)
    }
    private func fixture() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".py")
        let script = """
        #!/usr/bin/python3
        import json, sys
        def send(msg): print(json.dumps([msg]), flush=True)
        send({"event":"app.start","params":{"appId":"app"}})
        send({"event":"app.log","params":{"appId":"app","log":"arguments:"+json.dumps(sys.argv[1:])}})
        send({"event":"app.started","params":{"appId":"app"}})
        for line in sys.stdin:
            command=json.loads(line)[0]
            send({"event":"app.log","params":{"appId":"app","log":command["method"]+str(command.get("params",{}).get("fullRestart",False))}})
            send({"id":command["id"],"result":{"code":0}})
            if command["method"]=="app.stop":
                send({"event":"app.stop","params":{"appId":"app"}})
                break
        """
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { throw SimFlutDockError.timeout("test") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    @MainActor func testIndependentProcessesCommandRoutingStateAndStopRun() async throws {
        let script = try fixture(); defer { try? FileManager.default.removeItem(at: script) }
        let manager = SessionManager(simulators: SimulatorService())
        let a = Project(name: "A", path: "/tmp"), b = Project(name: "B", path: "/tmp")
        let device = SimulatorDevice(udid: "D", name: "Test", state: "Booted")
        let sa = manager.session(for: a.id), sb = manager.session(for: b.id)
        try sa.start(executable: script.path, project: a, device: device, bundleID: "com.test.a", captureDartConsole: false)
        try sb.start(executable: script.path, project: b, device: device, bundleID: "com.test.b", captureDartConsole: false)
        defer { sa.stop(); sb.stop() }
        try await wait { sa.state == .running && sb.state == .running }
        XCTAssertFalse(sa.canRun); XCTAssertTrue(sa.canStop)
        sa.restart(full: false); XCTAssertEqual(sa.state, .reloading)
        sa.restart(full: true) // conflicting operation must be ignored
        try await wait { sa.state == .running && sa.logs.contains { $0.text == "app.restartFalse" } }
        XCTAssertFalse(sb.logs.contains { $0.text.contains("app.restart") })
        XCTAssertFalse(sa.logs.contains { $0.text == "app.restartTrue" })
        sb.restart(full: true); try await wait { sb.state == .running && sb.logs.contains { $0.text == "app.restartTrue" } }
        XCTAssertEqual(manager.conflictingProject(bundleID: "com.test.a", deviceID: "D", excluding: b.id), a.id)
        XCTAssertNil(manager.conflictingProject(bundleID: "com.test.a", deviceID: "D2", excluding: b.id))
        sa.stop(); XCTAssertEqual(sa.state, .stopping)
        try await wait { sa.canRun }
        XCTAssertTrue(sb.isAlive); XCTAssertEqual(sa.state, .ready)
        try sa.start(executable: script.path, project: a, device: device, bundleID: "com.test.a", captureDartConsole: false)
        try await wait { sa.state == .running }
        let shutdown = Task { await manager.waitForStop() }
        while !manager.shuttingDown { await Task.yield() }
        let late = Project(name: "Late launch", path: "/tmp")
        manager.run(project: late, device: device, globalSDK: nil)
        XCTAssertNil(manager.sessions[late.id])
        await shutdown.value; XCTAssertFalse(manager.hasActiveSessions)
    }
    @MainActor func testUnexpectedExitDoesNotLeaveRememberedLiveSession() async throws {
        let session = FlutterSession(projectID: UUID())
        try session.start(executable: "/usr/bin/true", project: Project(name: "Exit", path: "/tmp"), device: SimulatorDevice(udid: "D", name: "D", state: "Booted"), bundleID: "com.test.exit", captureDartConsole: false)
        try await wait { !session.isAlive }
        XCTAssertEqual(session.state, .disconnected); XCTAssertTrue(session.canRun); XCTAssertFalse(session.canStop)
    }
    @MainActor func testPhysicalModesStartWithoutInitialPauseAndOnlyDebugAllowsHotRestart() async throws {
        let script = try fixture(); defer { try? FileManager.default.removeItem(at: script) }
        let phone = SimulatorDevice(udid: "PHONE", name: "iPhone", state: "Подключено", isPhysical: true)
        for mode in LaunchMode.allCases {
            var project = Project(name: "Physical", path: "/tmp")
            project.launch.setMode(mode)
            let manager = SessionManager(simulators: SimulatorService())
            let session = manager.session(for: project.id)
            try session.start(executable: script.path, project: project, device: phone, bundleID: "com.test.physical")
            defer { session.stop() }
            try await wait { session.state == .running }
            let argumentsLog = try XCTUnwrap(session.logs.first { $0.text.hasPrefix("arguments:") })
            let args = try JSONDecoder().decode([String].self, from: Data(argumentsLog.text.dropFirst("arguments:".count).utf8))
            XCTAssertTrue(args.contains("--" + mode.rawValue))
            XCTAssertFalse(args.contains("--start-paused"))
            XCTAssertEqual(Array(args.suffix(2)), ["-d", phone.id])
            XCTAssertEqual(session.canRestart, mode == .debug)
            if mode == .debug {
                session.restart(full: true)
                try await wait { session.state == .running && session.logs.contains { $0.text == "app.restartTrue" } }
            } else {
                session.restart(full: false); session.restart(full: true)
                XCTAssertEqual(session.state, .running)
                XCTAssertFalse(session.logs.contains { $0.text.contains("app.restart") })
            }
            await manager.foreground(project.id)
            XCTAssertFalse(session.logs.contains { $0.text.contains(L10n.text("Could not bring the app to the foreground: {0}", "").components(separatedBy: ":")[0]) })
            session.stop(); try await wait { session.canRun }
            XCTAssertTrue(session.logs.contains { $0.text == "app.stopFalse" })
        }
    }
    @MainActor func testPreparationCancellationAndLogLimit() async throws {
        let session = FlutterSession(projectID: UUID())
        let project = Project(name: "A", path: "/tmp"), device = SimulatorDevice(udid: "D", name: "D", state: "Shutdown")
        session.prepare(project: project, device: device); session.stop()
        XCTAssertFalse(session.canRun)
        session.launchFailed(CancellationError()); XCTAssertTrue(session.canRun); XCTAssertEqual(session.state, .ready)
        session.prepare(project: project, device: device); session.launchFailed(SimFlutDockError.message("failure"))
        XCTAssertEqual(session.state, .error); XCTAssertTrue(session.canRun)
        for n in 0..<2200 { session.append("log \(n)") }
        XCTAssertEqual(session.logs.count, 2000)
        session.clearLogs(); XCTAssertTrue(session.logs.isEmpty)
    }
    func testTimeoutKillsOwnedDescendantAndReturnsPromptly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("child.pid")
        let child = "import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); open(\"" + pidFile.path + "\",\"w\").write(str(os.getpid())); time.sleep(15)"
        let encoded = Data(child.utf8).base64EncodedString()
        let parent = "import subprocess; subprocess.Popen([\"/usr/bin/python3\",\"-c\", \"import base64; exec(base64.b64decode('" + encoded + "'))\"]).wait()"
        let begin = Date()
        do { _ = try await ToolRunner.run("/usr/bin/python3", ["-c", parent], timeout: 1); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error is SimFlutDockError) }
        XCTAssertLessThan(Date().timeIntervalSince(begin), 3)
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8))!
        defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        // A killed orphan may briefly remain a zombie until launchd reaps it.
        let result = try await ToolRunner.run("/bin/ps", ["-o", "stat=", "-p", String(pid)])
        XCTAssertTrue(result.status != 0 || result.text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"), result.text)
    }
    func testExitedParentDoesNotWaitForInheritedPipe() async throws {
        let begin = Date()
        let result = try await ToolRunner.run("/usr/bin/python3", ["-c", "import subprocess; subprocess.Popen(['/bin/sleep','2']); print('parent finished',flush=True)"], timeout: 4)
        XCTAssertLessThan(Date().timeIntervalSince(begin), 1.5)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.text.contains("parent finished"))
    }
    func testToolDrainsBothStreamsWithoutTruncatingSmallOutput() async throws {
        let result = try await ToolRunner.run("/usr/bin/python3", ["-c", "import sys; sys.stdout.write('a'*200000); sys.stderr.write('b'*200000)"])
        XCTAssertEqual(result.stdout, Data(repeating: 97, count: 200000))
        XCTAssertEqual(result.stderr, Data(repeating: 98, count: 200000))
    }
    func testToolCancellationReturnsCancellationErrorPromptly() async throws {
        let task = Task { try await ToolRunner.run("/bin/sleep", ["15"], timeout: 30) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let begin = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(begin), 1)
    }
    func testToolTimeout() async throws {
        do { _ = try await ToolRunner.run("/bin/sleep", ["10"], timeout: 0.03); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains(L10n.text("Timed out: {0}. See the logs for details.", "").components(separatedBy: ":")[0])) }
    }
}

final class SimulatorToolsTests: XCTestCase {
    private let device = SimulatorDevice(udid: "SIM-A", name: "iPhone", state: "Booted")
    func testCommandsAlwaysTargetExactDeviceAndApplication() throws {
        XCTAssertEqual(try SimulatorToolCommand.arguments(device: device, operation: "permissions", value: "com.example.app"),
                       ["simctl", "privacy", "SIM-A", "reset", "all", "com.example.app"])
        XCTAssertEqual(try SimulatorToolCommand.arguments(device: device, operation: "container", value: "com.example.app"),
                       ["simctl", "get_app_container", "SIM-A", "com.example.app", "data"])
        XCTAssertEqual(try SimulatorToolCommand.arguments(device: device, operation: "openurl", value: "myapp://profile?id=42"),
                       ["simctl", "openurl", "SIM-A", "myapp://profile?id=42"])
        XCTAssertThrowsError(try SimulatorToolCommand.arguments(device: device, operation: "permissions", value: ""))
        XCTAssertThrowsError(try SimulatorToolCommand.arguments(device: device, operation: "unknown", value: "com.example.app"))
    }
    func testUnavailableOrAmbiguousTargetsCannotExecuteTools() {
        for target in [
            SimulatorDevice(udid: "SIM-B", name: "Off", state: "Shutdown"),
            SimulatorDevice(udid: "booted", name: "Ambiguous", state: "Booted"),
            SimulatorDevice(udid: "PHONE", name: "Phone", state: "Booted", isPhysical: true),
            SimulatorDevice(udid: "MAC", name: "Mac", state: "Booted", targetPlatform: "darwin", isEmulator: false)
        ] {
            XCTAssertThrowsError(try SimulatorToolCommand.arguments(device: target, operation: "permissions", value: "com.example.app"))
        }
    }
    func testLinksRequireUsableSchemeAndPreserveQuery() throws {
        XCTAssertEqual(try SavedDeepLink.validatedURL("  myapp://order/42?name=A%20B&mode=test  "), "myapp://order/42?name=A%20B&mode=test")
        XCTAssertEqual(try SavedDeepLink.validatedURL("https://example.com/profile"), "https://example.com/profile")
        for invalid in ["", "profile/42", "https://", "https://example.com/a b", "file:///tmp/a", "javascript:alert(1)", "myapp://a\nb"] {
            XCTAssertThrowsError(try SavedDeepLink.validatedURL(invalid), invalid)
        }
    }
    func testOlderProjectArchivesDecodeWithoutLinks() throws {
        let project = Project(name: "Existing", path: "/tmp/existing")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        json.removeValue(forKey: "deepLinks")
        let restored = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, project)
    }
    @MainActor func testLinksPersistIndependentlyAcrossProjectsAndCanBeRemoved() throws {
        struct Archive: Encodable { let projects: [Project]; let selectedID: UUID }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("projects.json")
        var first = Project(name: "A", path: "/tmp/a")
        let second = Project(name: "B", path: "/tmp/b")
        try JSONEncoder().encode(Archive(projects: [first, second], selectedID: first.id)).write(to: file)
        let store = ProjectStore(file: file)
        let link = SavedDeepLink(name: "Profile", url: "myapp://profile")
        first.deepLinks = [link]; store.update(first)
        let restored = ProjectStore(file: file)
        XCTAssertEqual(restored.projects[0].deepLinks, [link])
        XCTAssertTrue(restored.projects[1].deepLinks.isEmpty)
        first.deepLinks[0].name = "My profile"; store.update(first)
        XCTAssertEqual(ProjectStore(file: file).projects[0].deepLinks[0].name, "My profile")
        first.deepLinks.removeAll(); store.update(first)
        XCTAssertTrue(ProjectStore(file: file).projects[0].deepLinks.isEmpty)
        XCTAssertNil(store.persistenceError)
    }
}

final class AutomaticDeviceSelectionTests: XCTestCase {
    func testBrowserDesktopAndAndroidAreNeverAutomaticTargets() {
        let chrome = SimulatorDevice(udid: "chrome", name: "Chrome", state: "Available", targetPlatform: "web-javascript", isEmulator: false)
        let desktop = SimulatorDevice(udid: "macos", name: "macOS", state: "Available", targetPlatform: "darwin", isEmulator: false)
        let android = SimulatorDevice(udid: "android", name: "Android", state: "Booted", targetPlatform: "android", isEmulator: true)
        let simulator = SimulatorDevice(udid: "sim", name: "iPhone", state: "Shutdown")
        XCTAssertEqual(AutomaticDeviceSelection.device(from: [chrome, desktop, android, simulator])?.id, simulator.id)
        XCTAssertNil(AutomaticDeviceSelection.device(from: [chrome, desktop, android]))
    }
    func testBootedSimulatorPreferredAndUnavailableSkipped() {
        let off = SimulatorDevice(udid: "off", name: "A", state: "Shutdown")
        let unavailable = SimulatorDevice(udid: "unavailable", name: "B", state: "Booted", isAvailable: false)
        let booted = SimulatorDevice(udid: "on", name: "C", state: "Booted")
        XCTAssertEqual(AutomaticDeviceSelection.device(from: [off, unavailable, booted])?.id, booted.id)
    }
}

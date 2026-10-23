import XCTest

@testable import SimFlutDockCore

final class DeviceCacheTests: XCTestCase {
    @MainActor func testCacheLoadsImmediatelyButRequiresDiscoveryBeforeLaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("devices.json")
        let android = SimulatorDevice(
            udid: "ANDROID", name: "Pixel", state: "Booted", targetPlatform: "android-arm64", isEmulator: true)
        let simulator = SimulatorDevice(udid: "SIM", name: "iPhone", state: "Booted")
        let service = SimulatorService(cacheFile: file)
        service.updateDevices(simulators: [simulator], flutterDevices: [android, simulator])
        XCTAssertEqual(service.devices.count, 2)
        XCTAssertEqual(service.currentDeviceIDs, [android.id, simulator.id])

        let restored = SimulatorService(cacheFile: file)
        XCTAssertEqual(restored.devices, service.devices)
        XCTAssertTrue(restored.currentDeviceIDs.isEmpty)
        restored.updateDevices(simulators: [simulator], flutterDevices: nil)
        XCTAssertEqual(restored.devices, service.devices, "A failed Flutter scan must keep Android visible")
        XCTAssertEqual(restored.currentDeviceIDs, [simulator.id])

        restored.updateDevices(simulators: [simulator], flutterDevices: [])
        XCTAssertEqual(restored.devices, [simulator], "A successful scan removes disconnected devices")
        XCTAssertEqual(SimulatorService(cacheFile: file).devices, [simulator])
    }

    @MainActor func testFreshDiscoveryReplacesCachedStateWhenOtherSourceFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SimulatorService(cacheFile: directory.appendingPathComponent("devices.json"))
        var simulator = SimulatorDevice(udid: "SIM", name: "iPhone", state: "Shutdown")
        service.updateDevices(simulators: [simulator], flutterDevices: [])
        simulator = SimulatorDevice(udid: "SIM", name: "iPhone", state: "Booted")
        service.updateDevices(simulators: nil, flutterDevices: [simulator])
        XCTAssertEqual(service.devices, [simulator])
        XCTAssertEqual(service.currentDeviceIDs, [simulator.id])
        service.updateDevices(simulators: nil, flutterDevices: nil)
        XCTAssertEqual(service.devices, [simulator])
        XCTAssertTrue(service.currentDeviceIDs.isEmpty)
    }

    @MainActor func testInvalidCacheDoesNotPreventDiscovery() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("invalid cache".utf8).write(to: file)
        let service = SimulatorService(cacheFile: file)
        XCTAssertTrue(service.devices.isEmpty)
        let phone = SimulatorDevice(udid: "PHONE", name: "iPhone", state: "Available", isPhysical: true)
        service.updateDevices(simulators: [], flutterDevices: [phone])
        XCTAssertEqual(SimulatorService(cacheFile: file).devices, [phone])
    }
}

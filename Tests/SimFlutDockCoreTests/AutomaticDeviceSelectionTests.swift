import XCTest

@testable import SimFlutDockCore

final class AutomaticDeviceSelectionTests: XCTestCase {
    func testBrowserDesktopAndAndroidAreNeverAutomaticTargets() {
        let chrome = SimulatorDevice(
            udid: "chrome", name: "Chrome", state: "Available", targetPlatform: "web-javascript", isEmulator: false)
        let desktop = SimulatorDevice(
            udid: "macos", name: "macOS", state: "Available", targetPlatform: "darwin", isEmulator: false)
        let android = SimulatorDevice(
            udid: "android", name: "Android", state: "Booted", targetPlatform: "android", isEmulator: true)
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

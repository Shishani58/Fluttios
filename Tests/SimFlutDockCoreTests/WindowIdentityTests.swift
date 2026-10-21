import XCTest

@testable import SimFlutDockCore

final class WindowIdentityTests: XCTestCase {
    private let device = SimulatorDevice(udid: "AABB-1234", name: "Demo iPhone 17 Pro", state: "Booted")
    func testClassicAndDeviceHubTitles() {
        for title in [
            device.name, device.name + " – iOS 26.5", device.name + " — iOS 26.5", device.name + " (26.5)",
            "  " + device.name + " - iOS 26.5  ", "Simulator aabb-1234",
        ] {
            XCTAssertTrue(SimulatorWindowIdentity.matches(title: title, device: device), title)
        }
    }
    func testDuplicateDeviceNameRequiresManualBindingEvenWithOneWindow() {
        let duplicate = SimulatorDevice(udid: "OTHER", name: device.name, state: "Shutdown")
        let title = device.name + " – iOS 26.5"
        XCTAssertFalse(
            SimulatorWindowIdentity.matches(title: title, device: device, knownDevices: [device, duplicate]))
        XCTAssertFalse(
            SimulatorWindowIdentity.matches(title: title, device: duplicate, knownDevices: [device, duplicate]))
        XCTAssertTrue(
            SimulatorWindowIdentity.matches(
                title: "Simulator " + device.id, device: device, knownDevices: [device, duplicate]))
        XCTAssertTrue(SimulatorWindowIdentity.matches(title: title, device: device, knownDevices: [device]))
    }
    func testDoesNotBindToAnotherDeviceOrManagementWindow() {
        for title in [
            "iPhone 17 Pro – iOS 26.5", device.name + " Max – iOS 26.5", "Device Hub", "Devices and Simulators",
        ] {
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

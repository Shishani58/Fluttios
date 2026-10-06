import XCTest
@testable import FluttiosCore

final class AutomaticPanelBindingTests: XCTestCase {
    func testAlreadyOpenSimulatorAndRepeatedRefresh() {
        var binding = AutomaticPanelBinding()
        let device = UUID()
        XCTAssertTrue(binding.update(windowIDs: [device], focusedID: nil))
        XCTAssertEqual(binding.windowID, device)
        // A refresh must not undo explicit hiding of the panel.
        XCTAssertFalse(binding.update(windowIDs: [device], focusedID: device))
    }

    func testNewSimulatorReplacesPreviouslyAttachedWindow() {
        var binding = AutomaticPanelBinding()
        let old = UUID(), launched = UUID()
        binding.update(windowIDs: [old], focusedID: old)
        XCTAssertTrue(binding.update(windowIDs: [old, launched], focusedID: old))
        XCTAssertEqual(binding.windowID, launched)
    }

    func testMultipleWindowsUseFocusWithoutArbitrarySelection() {
        var binding = AutomaticPanelBinding()
        let first = UUID(), second = UUID()
        XCTAssertFalse(binding.update(windowIDs: [first, second], focusedID: nil))
        XCTAssertNil(binding.windowID)
        XCTAssertTrue(binding.update(windowIDs: [first, second], focusedID: second))
        XCTAssertEqual(binding.windowID, second)
        XCTAssertFalse(binding.update(windowIDs: [first, second], focusedID: first))
        XCTAssertEqual(binding.windowID, first)
    }

    func testHostTerminationAndRelaunch() {
        var binding = AutomaticPanelBinding()
        let original = UUID(), relaunched = UUID()
        binding.update(windowIDs: [original], focusedID: original)
        XCTAssertFalse(binding.update(windowIDs: [], focusedID: original))
        XCTAssertNil(binding.windowID)
        XCTAssertTrue(binding.update(windowIDs: [relaunched], focusedID: nil))
        XCTAssertEqual(binding.windowID, relaunched)
    }
}

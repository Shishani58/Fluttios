import XCTest

@testable import SimFlutDockCore

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
            if y >= size.height {
                XCTAssertLessThanOrEqual(panel.maxY, window.minY)
            } else {
                XCTAssertEqual(panel.minY, window.maxY + 8)
            }
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
        let originalPanel = PanelPlacement.frame(
            window: original, size: PanelPlacement.attachedSize(window: original, visible: visible), visible: visible)
        let resizedPanel = PanelPlacement.frame(
            window: resized, size: PanelPlacement.attachedSize(window: resized, visible: visible), visible: visible)
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
        let frame = PanelPlacement.frame(
            window: window, size: CGSize(width: 360, height: 40), visible: visible, side: .right)
        XCTAssertEqual(frame.maxY, window.minY - 8)
        XCTAssertTrue(visible.contains(frame))
        XCTAssertFalse(window.intersects(frame))
    }
    func testAttachedLayoutUsesVerticalColumnOnEitherSide() {
        let visible = CGRect(x: -1440, y: 40, width: 1440, height: 860)
        let window = CGRect(x: -900, y: 100, width: 400, height: 600)
        for side in [PanelSide.left, .right] {
            let layout = PanelPlacement.attachedLayout(
                window: window, horizontalSize: CGSize(width: 400, height: 70),
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
        let fallback = PanelPlacement.attachedLayout(
            window: crowded, horizontalSize: horizontal, verticalSize: vertical, visible: visible, side: .right)
        XCTAssertEqual(fallback.side, .below)
        XCTAssertEqual(fallback.frame.size, horizontal)
        XCTAssertFalse(crowded.intersects(fallback.frame))
        let moved = CGRect(x: 10, y: 200, width: 400, height: 600)
        let restored = PanelPlacement.attachedLayout(
            window: moved, horizontalSize: horizontal, verticalSize: vertical, visible: visible, side: .right)
        XCTAssertEqual(restored.side, .right)
        XCTAssertEqual(restored.frame.size, vertical)
        let tall = CGRect(x: 10, y: 50, width: 400, height: 840)
        let sideFallback = PanelPlacement.attachedLayout(
            window: tall, horizontalSize: horizontal, verticalSize: vertical, visible: visible, side: .above)
        XCTAssertEqual(sideFallback.side, .right)
        XCTAssertEqual(sideFallback.frame.size, vertical)
        XCTAssertTrue(visible.contains(sideFallback.frame))
    }
    func testAXConversionWithDisplayAbovePrimary() {
        let rect = PanelPlacement.appKitRect(ax: CGRect(x: -1000, y: -700, width: 400, height: 600), primaryTop: 900)
        XCTAssertEqual(rect.minY, 1000)
        XCTAssertEqual(rect.minX, -1000)
    }
    func testBelowAndAboveFallback() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 570, height: 80)
        let below = PanelPlacement.frame(
            window: CGRect(x: 500, y: 200, width: 400, height: 600), size: size, visible: visible)
        XCTAssertEqual(below.minY, 112)
        let above = PanelPlacement.frame(
            window: CGRect(x: 500, y: 20, width: 400, height: 600), size: size, visible: visible)
        XCTAssertEqual(above.minY, 628)
        XCTAssertTrue(visible.contains(above))
    }
    func testOffsetClampedOnNegativeMonitor() {
        let visible = CGRect(x: -1440, y: 40, width: 1440, height: 860)
        let frame = PanelPlacement.frame(
            window: CGRect(x: -400, y: 50, width: 350, height: 700), size: CGSize(width: 570, height: 80),
            visible: visible, offset: CGSize(width: 900, height: -300))
        XCTAssertTrue(visible.contains(frame))
        XCTAssertEqual(frame.maxX, 0)
        XCTAssertEqual(frame.minY, 40)
    }
}

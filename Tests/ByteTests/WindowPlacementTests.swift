import XCTest
@testable import Byte

final class WindowPlacementTests: XCTestCase {
    func testSeparatedDisplaysNeverLeavePanelInGap() throws {
        let left = CGRect(x: -1600, y: 200, width: 1000, height: 700)
        let right = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for x in stride(from: -1900, through: 1600, by: 50) {
            let frame = try XCTUnwrap(WindowPlacement.frame(anchor: CGPoint(x: x, y: 600),
                size: CGSize(width: 500, height: 650), displays: [left, right]))
            XCTAssertTrue(left.contains(frame) || right.contains(frame))
        }
    }

    func testUnpluggedDisplayAndOversizedPanelFitRemainingVisibleFrame() throws {
        let visible = CGRect(x: 40, y: 60, width: 640, height: 400)
        let frame = try XCTUnwrap(WindowPlacement.frame(anchor: CGPoint(x: -2000, y: 1600),
            size: CGSize(width: 1000, height: 1200), displays: [visible]))
        XCTAssertEqual(frame, visible)
        XCTAssertNil(WindowPlacement.frame(anchor: .zero, size: frame.size, displays: []))
    }
}

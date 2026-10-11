import CoreGraphics
import XCTest
@testable import VisaPassage

/// The Explore map's zoom and pan (`MapViewport`): cover at 1, contain at the
/// minimum, 8× at most, anchored zooms, and pans that never open a gap.
final class MapViewportTests: XCTestCase {
    /// A 2:1 world in a 300×200 frame: cover scales by height (200), contain by width (150).
    private let bounds = PlaneBounds(minX: 0, minY: 0, maxX: 2, maxY: 1)
    private let size = CGSize(width: 300, height: 200)

    func testCoverFillsHeightAndCropsSides() {
        let base = MapViewport.coverFit(bounds: bounds, size: size)
        XCTAssertEqual(base.scale, 200, accuracy: 0.001)
        XCTAssertEqual(base.offsetX, -50, accuracy: 0.001, "400pt of land, centred in 300pt")
        XCTAssertEqual(MapViewport.minZoom(bounds: bounds, size: size), 0.75, accuracy: 0.001)
    }

    func testZoomClampsToRange() {
        XCTAssertEqual(MapViewport(k: 20).clamped(bounds: bounds, size: size).k, MapViewport.maxZoom)
        XCTAssertEqual(MapViewport(k: 0).clamped(bounds: bounds, size: size).k, 0.75, accuracy: 0.001)
    }

    func testAnchoredZoomKeepsThePointStill() {
        let base = MapViewport.coverFit(bounds: bounds, size: size)
        let anchor = CGPoint(x: 120, y: 80)
        let before = MapViewport()
        let after = before.zoomed(to: 3, anchor: anchor)
        // The plane point under the anchor before is still under it after.
        let plane = CGPoint(x: (120 - base.offsetX) / base.scale, y: 1 - (80 - base.offsetY) / base.scale)
        let p = after.fit(base).screen(plane)
        XCTAssertEqual(p.x, anchor.x, accuracy: 0.001)
        XCTAssertEqual(p.y, anchor.y, accuracy: 0.001)
    }

    func testPanNeverOpensAGap() {
        let base = MapViewport.coverFit(bounds: bounds, size: size)
        let far = MapViewport(k: 1, t: CGSize(width: 500, height: 90)).clamped(bounds: bounds, size: size)
        let fit = far.fit(base)
        XCTAssertEqual(fit.screen(CGPoint(x: 0, y: 1)).x, 0, accuracy: 0.001, "Left edge stops at the frame's edge")
        XCTAssertEqual(far.t.height, 0, accuracy: 0.001, "At cover the height already fills: no vertical pan")
    }

    func testLiveTransformMapsCommittedToCurrent() {
        let a = MapViewport(k: 1, t: CGSize(width: -40, height: 0))
        let b = MapViewport(k: 2, t: CGSize(width: -150, height: -60))
        let m = a.transform(to: b)
        let base = MapViewport.coverFit(bounds: bounds, size: size)
        let plane = CGPoint(x: 1.3, y: 0.4)
        let viaTransform = a.fit(base).screen(plane).applying(m)
        let direct = b.fit(base).screen(plane)
        XCTAssertEqual(viaTransform.x, direct.x, accuracy: 0.001)
        XCTAssertEqual(viaTransform.y, direct.y, accuracy: 0.001)
    }
}

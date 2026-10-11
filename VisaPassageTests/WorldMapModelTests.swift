import CoreGraphics
import XCTest
@testable import VisaPassage

/// The Explore map's geometry: the web's Miller projection with the seam in
/// the Bering Strait, so no country streaks across the map, and hit-testing
/// on the cached plane-space paths.
@MainActor
final class WorldMapModelTests: XCTestCase {
    private func loadedModel() async -> WorldMapModel {
        let model = WorldMapModel()
        await model.loadAtlasIfNeeded()
        model.projectIfNeeded(catalog: [
            Country(iso2: "RU", name: "Russia", isoNumeric: "643"),
            Country(iso2: "SA", name: "Saudi Arabia", isoNumeric: "682"),
            Country(iso2: "FJ", name: "Fiji", isoNumeric: "242"),
            Country(iso2: "US", name: "United States", isoNumeric: "840"),
        ])
        return model
    }

    func testRussiaIsWholeAndInsideTheWindow() async {
        let model = await loadedModel()
        XCTAssertFalse(model.loading)
        guard let box = model.mainBox("RU") else { return XCTFail("Russia missing") }
        let window = MillerProjection.window
        // Russia spans ~180° of longitude (π in plane x), not the whole world.
        XCTAssertLessThan(box.width, 3.4, "Russia's main landmass must not wrap around the seam")
        XCTAssertGreaterThan(box.minX, window.minX)
        XCTAssertLessThanOrEqual(box.maxX, window.maxX + 0.01, "Chukotka sits inside the east edge")
    }

    func testRingsNeverJumpAcrossTheMap() {
        // A ring crossing ±180° (Fiji's, Russia's) must unwrap, not jump.
        let ring = [GeoCoordinate(lon: 178, lat: -17), GeoCoordinate(lon: -179.5, lat: -17),
                    GeoCoordinate(lon: -179.5, lat: -16), GeoCoordinate(lon: 178, lat: -16)]
        let rings = MillerProjection.rings(for: ring)
        for r in rings {
            for (a, b) in zip(r, r.dropFirst()) {
                XCTAssertLessThan(abs(a.x - b.x), 1, "No jump between neighbouring points")
            }
        }
    }

    func testHitTestFindsTheCountryUnderAPoint() async {
        let model = await loadedModel()
        let size = CGSize(width: 337, height: 242)
        let fit = MapViewport.coverFit(bounds: MillerProjection.window, size: size)
        // Riyadh.
        let riyadh = fit.screen(MillerProjection.project(lonDeg: 46.7, latDeg: 24.7))
        XCTAssertEqual(model.country(at: riyadh, fit: fit), "SA")
        let pacific = fit.screen(MillerProjection.project(lonDeg: -140, latDeg: 0))
        XCTAssertNil(model.country(at: pacific, fit: fit))
    }

    func testFittingFramesTheRect() {
        let window = MillerProjection.window
        let size = CGSize(width: 337, height: 242)
        let rect = CGRect(x: 0.5, y: 0.5, width: 0.6, height: 0.3)
        let v = MapViewport.fitting(rect, bounds: window, size: size, padding: 20, maxK: 6)
        let fit = v.fit(MapViewport.coverFit(bounds: window, size: size))
        let c = fit.screen(CGPoint(x: rect.midX, y: rect.midY))
        XCTAssertEqual(c.x, size.width / 2, accuracy: 1)
        XCTAssertEqual(c.y, size.height / 2, accuracy: 1)
        XCTAssertGreaterThan(v.k, 1)
    }
}

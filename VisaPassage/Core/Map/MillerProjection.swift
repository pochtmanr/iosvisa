import CoreGraphics
import Foundation

/// The map projection the web uses (`web/src/components/map/atlas.ts`): Miller
/// cylindrical, centred on 11°E so its seam runs through the Bering Strait
/// (169°W) instead of the antimeridian. Plane space: x = rotated longitude in
/// radians, y = Miller latitude, y up.
///
/// Cylindrical on purpose: the land window is a rectangle, so a zoomed map
/// pans edge to edge with no empty corners (Equal Earth's curved sides left
/// blank wedges at the frame's corners).
enum MillerProjection {
    /// Centre meridian. The seam (±180° from it) falls in open water between
    /// Alaska (168°W) and Chukotka (169.7°W), so Russia draws whole.
    static let centreLon = 11.0

    /// Longitude rotated onto the centre meridian, in [-180, 180).
    static func rotated(lonDeg: Double) -> Double {
        var l = (lonDeg - centreLon).truncatingRemainder(dividingBy: 360)
        if l >= 180 { l -= 360 }
        if l < -180 { l += 360 }
        return l
    }

    /// Plane point for an already-rotated longitude (degrees, may run past ±180
    /// for an unwrapped ring) and a latitude.
    static func plane(rotatedLonDeg l: Double, latDeg: Double) -> CGPoint {
        let phi = latDeg * .pi / 180
        return CGPoint(x: l * .pi / 180, y: 1.25 * log(tan(.pi / 4 + 0.4 * phi)))
    }

    static func project(lonDeg: Double, latDeg: Double) -> CGPoint {
        plane(rotatedLonDeg: rotated(lonDeg: lonDeg), latDeg: latDeg)
    }

    /// The land window, the web's VIEW_* crop (x 9…951, y 4…474 in its 960-wide
    /// frame) in plane units: Alaska's mainland to Chukotka and the far
    /// Aleutians, north Greenland to Cape Horn. The map fits, pans and clips
    /// to this, never to the raw geometry (wrapped copies run past it).
    static let window: PlaneBounds = {
        let s = 150.2422662787492, tx = 480.0, ty = 306.0361082700306
        return PlaneBounds(
            minX: (9 - tx) / s,
            minY: (ty - 474) / s,
            maxX: (951 - tx) / s,
            maxY: (ty - 4) / s
        )
    }()

    /// Project one ring, unwrapped so it never jumps across the map. Source
    /// rings that cross ±180° (Russia, Fiji) used to draw a stripe across the
    /// whole world. A ring that still straddles the seam after rotation (a
    /// Bering Sea island) also comes back shifted by a full turn, so both of
    /// its halves show at the window's edges.
    static func rings(for ring: [GeoCoordinate]) -> [[CGPoint]] {
        guard ring.count > 2 else { return [] }
        var lons: [Double] = []
        lons.reserveCapacity(ring.count)
        var prev = rotated(lonDeg: ring[0].lon)
        lons.append(prev)
        for c in ring.dropFirst() {
            var l = rotated(lonDeg: c.lon)
            while l - prev > 180 { l -= 360 }
            while l - prev < -180 { l += 360 }
            lons.append(l)
            prev = l
        }
        let lo = lons.min() ?? 0, hi = lons.max() ?? 0
        var shifts: [Double] = [0]
        if hi > 180 { shifts.append(-360) }
        if lo < -180 { shifts.append(360) }
        return shifts.map { shift in
            zip(lons, ring).map { l, c in plane(rotatedLonDeg: l + shift, latDeg: c.lat) }
        }
    }
}

import CoreGraphics
import Foundation

/// The Equal Earth pseudocylindrical projection (Šavrič, Patterson & Jenny
/// 2018) — the same projection the web checker uses via d3 `geoEqualEarth`.
/// Pure forward transform from lon/lat (degrees) to an abstract plane (y up).
enum EqualEarth {
    private static let a1 = 1.340264
    private static let a2 = -0.081106
    private static let a3 = 0.000893
    private static let a4 = 0.003796
    private static let m = 0.8660254037844386 // √3 / 2

    /// Project a coordinate to plane space (y increases northward).
    static func project(lonDeg: Double, latDeg: Double) -> CGPoint {
        let lambda = lonDeg * .pi / 180
        let phi = latDeg * .pi / 180
        let theta = asin(m * sin(phi))
        let t2 = theta * theta
        let t6 = t2 * t2 * t2
        let x = lambda * cos(theta) / (m * (a1 + 3 * a2 * t2 + t6 * (7 * a3 + 9 * a4 * t2)))
        let y = theta * (a1 + a2 * t2 + t6 * (a3 + a4 * t2))
        return CGPoint(x: x, y: y)
    }
}

/// Maps projected plane coordinates into a target rect, preserving aspect ratio
/// and flipping the y-axis to screen space. Built once for a given size from the
/// plane bounding box of the rendered geometry.
struct ProjectionFit: Sendable {
    let scale: Double
    let offsetX: Double
    let offsetY: Double
    let planeMinX: Double
    let planeMaxY: Double

    /// Fit `bounds` (a plane bounding box) into `size` with `inset` padding.
    static func fitting(bounds: PlaneBounds, into size: CGSize, inset: Double = 0) -> ProjectionFit {
        let usableW = max(1, Double(size.width) - inset * 2)
        let usableH = max(1, Double(size.height) - inset * 2)
        let spanX = max(0.000001, bounds.maxX - bounds.minX)
        let spanY = max(0.000001, bounds.maxY - bounds.minY)
        let scale = min(usableW / spanX, usableH / spanY)
        // Center the scaled content inside the usable area.
        let drawnW = spanX * scale
        let drawnH = spanY * scale
        let offsetX = inset + (usableW - drawnW) / 2
        let offsetY = inset + (usableH - drawnH) / 2
        return ProjectionFit(
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY,
            planeMinX: bounds.minX,
            planeMaxY: bounds.maxY
        )
    }

    /// Plane point → screen point (y flipped so north is up).
    func screen(_ plane: CGPoint) -> CGPoint {
        CGPoint(
            x: offsetX + (Double(plane.x) - planeMinX) * scale,
            y: offsetY + (planeMaxY - Double(plane.y)) * scale
        )
    }
}

/// Axis-aligned bounding box in projected plane space.
struct PlaneBounds: Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    static let empty = PlaneBounds(
        minX: .greatestFiniteMagnitude, minY: .greatestFiniteMagnitude,
        maxX: -.greatestFiniteMagnitude, maxY: -.greatestFiniteMagnitude
    )

    mutating func expand(_ p: CGPoint) {
        minX = Swift.min(minX, Double(p.x)); maxX = Swift.max(maxX, Double(p.x))
        minY = Swift.min(minY, Double(p.y)); maxY = Swift.max(maxY, Double(p.y))
    }

    var isValid: Bool { maxX >= minX && maxY >= minY }
}

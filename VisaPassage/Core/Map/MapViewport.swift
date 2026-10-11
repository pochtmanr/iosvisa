import CoreGraphics
import Foundation

/// Zoom and pan over a fitted map, the web `useMapZoom` on a phone: zoom 1
/// covers the frame (the land fills its height, the sides crop), zooming out
/// stops when the whole world fits, zooming in stops at 8×. Pans are clamped
/// so the land never leaves a gap at an edge it could cover. Pure, so the
/// gestures and the tests share it.
struct MapViewport: Equatable, Sendable {
    /// Scale over the cover fit.
    var k: Double = 1
    /// Screen-space translation, applied after scaling.
    var t: CGSize = .zero

    static let maxZoom: Double = 8

    /// The plane box scaled to cover `size`, centred.
    static func coverFit(bounds: PlaneBounds, size: CGSize) -> ProjectionFit {
        let spanX = max(0.000001, bounds.maxX - bounds.minX)
        let spanY = max(0.000001, bounds.maxY - bounds.minY)
        let scale = max(Double(size.width) / spanX, Double(size.height) / spanY)
        return ProjectionFit(
            scale: scale,
            offsetX: (Double(size.width) - spanX * scale) / 2,
            offsetY: (Double(size.height) - spanY * scale) / 2,
            planeMinX: bounds.minX,
            planeMaxY: bounds.maxY
        )
    }

    /// The smallest zoom: the whole box fits (contain over cover).
    static func minZoom(bounds: PlaneBounds, size: CGSize) -> Double {
        let spanX = max(0.000001, bounds.maxX - bounds.minX)
        let spanY = max(0.000001, bounds.maxY - bounds.minY)
        let w = Double(size.width), h = Double(size.height)
        guard w > 0, h > 0 else { return 1 }
        return min(w / spanX, h / spanY) / max(w / spanX, h / spanY)
    }

    /// The projection at this zoom: `screen = k · cover + t`.
    func fit(_ base: ProjectionFit) -> ProjectionFit {
        ProjectionFit(
            scale: base.scale * k,
            offsetX: base.offsetX * k + Double(t.width),
            offsetY: base.offsetY * k + Double(t.height),
            planeMinX: base.planeMinX,
            planeMaxY: base.planeMaxY
        )
    }

    /// Zoom to `newK` keeping the screen point `anchor` still.
    func zoomed(to newK: Double, anchor: CGPoint) -> MapViewport {
        let r = newK / k
        return MapViewport(
            k: newK,
            t: CGSize(width: anchor.x - r * (anchor.x - t.width),
                      height: anchor.y - r * (anchor.y - t.height))
        )
    }

    /// Zoom inside its range, then pan so the land covers every edge it can
    /// (an axis narrower than the frame is centred).
    func clamped(bounds: PlaneBounds, size: CGSize) -> MapViewport {
        let base = Self.coverFit(bounds: bounds, size: size)
        var out = self
        out.k = min(max(k, Self.minZoom(bounds: bounds, size: size)), Self.maxZoom)
        let spanX = (bounds.maxX - bounds.minX) * base.scale * out.k
        let spanY = (bounds.maxY - bounds.minY) * base.scale * out.k
        out.t.width = Self.clampAxis(t: Double(out.t.width), origin: base.offsetX * out.k,
                                     span: spanX, frame: Double(size.width))
        out.t.height = Self.clampAxis(t: Double(out.t.height), origin: base.offsetY * out.k,
                                      span: spanY, frame: Double(size.height))
        return out
    }

    private static func clampAxis(t: Double, origin: Double, span: Double, frame: Double) -> CGFloat {
        // The land's leading edge sits at origin + t.
        if span <= frame { return CGFloat((frame - span) / 2 - origin) }
        let lead = min(max(origin + t, frame - span), 0)
        return CGFloat(lead - origin)
    }

    /// Frame a plane rect (a route's two countries): it fills the frame less
    /// `padding`, capped at `maxK`, centred, then clamped like any pan (web
    /// `fitBounds`, used for the auto-zoom on a pick).
    static func fitting(_ rect: CGRect, bounds: PlaneBounds, size: CGSize,
                        padding: Double = 28, maxK: Double = 4) -> MapViewport {
        let base = coverFit(bounds: bounds, size: size)
        let w = max(0.000001, Double(rect.width) * base.scale)
        let h = max(0.000001, Double(rect.height) * base.scale)
        let k = min(maxK, (Double(size.width) - padding * 2) / w,
                    (Double(size.height) - padding * 2) / h)
        let c = base.screen(CGPoint(x: rect.midX, y: rect.midY))
        // fit(base).screen(p) = k · base.screen(p) + t
        let t = CGSize(width: Double(size.width) / 2 - k * Double(c.x),
                       height: Double(size.height) / 2 - k * Double(c.y))
        return MapViewport(k: k, t: t).clamped(bounds: bounds, size: size)
    }

    /// Centre a plane point horizontally (and vertically when there is room).
    func centring(_ plane: CGPoint, base: ProjectionFit, size: CGSize) -> MapViewport {
        let p = fit(base).screen(plane)
        var out = self
        out.t.width += size.width / 2 - p.x
        out.t.height += size.height / 2 - p.y
        return out
    }

    /// The affine step from `self` to `other` (live gestures move the drawn
    /// canvas instead of redrawing it).
    func transform(to other: MapViewport) -> CGAffineTransform {
        let r = other.k / k
        return CGAffineTransform(a: r, b: 0, c: 0, d: r,
                                 tx: other.t.width - r * t.width,
                                 ty: other.t.height - r * t.height)
    }
}

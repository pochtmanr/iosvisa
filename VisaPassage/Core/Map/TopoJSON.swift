import Foundation

/// A lon/lat coordinate (degrees) on the globe.
struct GeoCoordinate: Sendable, Hashable {
    var lon: Double
    var lat: Double
}

/// A country's decoded outline: one or more rings (outer + holes), already
/// converted from TopoJSON arcs to absolute lon/lat. Keyed by ISO numeric.
struct CountryGeometry: Sendable, Hashable {
    let numericID: String
    let name: String
    /// All rings flattened across the country's polygons. Each ring is a closed
    /// loop of coordinates; rendered as even-odd subpaths so lakes carve out.
    let rings: [[GeoCoordinate]]
}

/// The whole-world geometry, keyed by zero-padded 3-digit ISO numeric id.
struct WorldAtlas: Sendable {
    let countries: [String: CountryGeometry]
}

/// Pure decoder for [TopoJSON](https://github.com/topojson) `Topology`
/// documents (the format of `world-atlas-50m.json`). Delta-decodes arcs, applies
/// the quantization transform, and stitches geometry arc-indices into rings —
/// no rendering, fully unit-testable.
enum TopoJSON {
    enum DecodeError: Error { case malformed }

    /// Load and decode a bundled topology resource.
    static func load(resource: String, bundle: Bundle = .main) throws -> WorldAtlas {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw DecodeError.malformed
        }
        return try decode(data: try Data(contentsOf: url))
    }

    static func decode(data: Data) throws -> WorldAtlas {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let transform = root["transform"] as? [String: Any],
            let scale = numbers(transform["scale"]), scale.count >= 2,
            let translate = numbers(transform["translate"]), translate.count >= 2,
            let rawArcs = root["arcs"] as? [[[Any]]],
            let objects = root["objects"] as? [String: Any]
        else { throw DecodeError.malformed }

        let sx = scale[0], sy = scale[1], tx = translate[0], ty = translate[1]

        // Delta-decode every arc into absolute lon/lat once.
        let arcs: [[GeoCoordinate]] = rawArcs.map { arc in
            var x = 0.0, y = 0.0
            var points: [GeoCoordinate] = []
            points.reserveCapacity(arc.count)
            for pair in arc where pair.count >= 2 {
                x += asDouble(pair[0])
                y += asDouble(pair[1])
                points.append(GeoCoordinate(lon: x * sx + tx, lat: y * sy + ty))
            }
            return points
        }

        // Find the GeometryCollection (named "countries" here, but tolerate any).
        let collection = (objects["countries"] as? [String: Any])
            ?? objects.values.compactMap { $0 as? [String: Any] }.first { $0["geometries"] != nil }
        guard let geometries = collection?["geometries"] as? [[String: Any]] else {
            throw DecodeError.malformed
        }

        var countries: [String: CountryGeometry] = [:]
        for geom in geometries {
            guard let numericID = idString(geom["id"]) else { continue } // skip disputed/unkeyed
            let name = ((geom["properties"] as? [String: Any])?["name"] as? String) ?? numericID
            let rings = rings(for: geom, arcs: arcs)
            guard !rings.isEmpty else { continue }
            let padded = pad(numericID)
            countries[padded] = CountryGeometry(numericID: padded, name: name, rings: rings)
        }
        return WorldAtlas(countries: countries)
    }

    // MARK: - Ring stitching

    private static func rings(for geom: [String: Any], arcs: [[GeoCoordinate]]) -> [[GeoCoordinate]] {
        switch geom["type"] as? String {
        case "Polygon":
            guard let polygon = geom["arcs"] as? [[Int]] else { return [] }
            return polygon.map { ring(indices: $0, arcs: arcs) }
        case "MultiPolygon":
            guard let multi = geom["arcs"] as? [[[Int]]] else { return [] }
            return multi.flatMap { polygon in polygon.map { ring(indices: $0, arcs: arcs) } }
        default:
            return []
        }
    }

    /// Concatenate the arcs of one ring, reversing negative indices (`~i`) and
    /// dropping the shared leading vertex of each subsequent arc.
    private static func ring(indices: [Int], arcs: [[GeoCoordinate]]) -> [GeoCoordinate] {
        var coords: [GeoCoordinate] = []
        for (position, index) in indices.enumerated() {
            var segment: [GeoCoordinate]
            if index < 0 {
                guard ~index < arcs.count else { continue }
                segment = arcs[~index].reversed()
            } else {
                guard index < arcs.count else { continue }
                segment = arcs[index]
            }
            if position > 0 && !segment.isEmpty { segment.removeFirst() }
            coords.append(contentsOf: segment)
        }
        return coords
    }

    // MARK: - Coercion helpers (JSONSerialization yields NSNumber)

    private static func numbers(_ any: Any?) -> [Double]? {
        (any as? [Any])?.map(asDouble)
    }

    private static func asDouble(_ any: Any) -> Double {
        (any as? NSNumber)?.doubleValue ?? (any as? Double) ?? Double(any as? Int ?? 0)
    }

    private static func idString(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func pad(_ id: String) -> String {
        guard id.count < 3 else { return id }
        return String(repeating: "0", count: 3 - id.count) + id
    }
}

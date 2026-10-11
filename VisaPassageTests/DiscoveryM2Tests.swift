import XCTest
@testable import VisaPassage

/// Pure-logic M2 tests: the multi-passport best-status reducer, the eligibility
/// fold, the TopoJSON decoder, and the Equal Earth projection. All headless —
/// no network or running app (live data is spot-checked on device per the plan).
final class DiscoveryM2Tests: XCTestCase {

    // MARK: - Best status across passports

    func testBestStatusPrefersStrongerRegime() {
        XCTAssertEqual(VisaStatus.best(.visaFree, .visaRequired), .visaFree)
        XCTAssertEqual(VisaStatus.best(.visaRequired, .visaFree), .visaFree)
        XCTAssertEqual(VisaStatus.best(.evisa, .visaOnArrival), .visaOnArrival)
        XCTAssertEqual(VisaStatus.best(.noAdmission, .evisa), .evisa)
        XCTAssertEqual(VisaStatus.best(.unknown, .visaRequired), .visaRequired)
    }

    func testBestByDestinationMergesPassports() {
        let rows = [
            req("US", "DE", .visaFree),
            req("IL", "DE", .visaRequired),     // DE → best should be visa_free
            req("US", "CN", .visaRequired),
            req("IL", "CN", .evisa),            // CN → best should be evisa
            req("US", "BR", .visaFree),         // single passport
        ]
        let best = VisaStatus.bestByDestination(rows)
        XCTAssertEqual(best["DE"], .visaFree)
        XCTAssertEqual(best["CN"], .evisa)
        XCTAssertEqual(best["BR"], .visaFree)
        XCTAssertNil(best["JP"])
    }

    func testBestByDestinationNormalizesCase() {
        let best = VisaStatus.bestByDestination([req("US", "de", .visaFree)])
        XCTAssertEqual(best["DE"], .visaFree)
    }

    // MARK: - Eligibility fold

    func testResolveUsesProductDefaultWithoutOverride() throws {
        let product = try makeProduct(defaultEligibility: "eligible", applicationMode: "ours",
                                      govFeeCents: 5000, processingTimeDays: 10)
        let resolved = ResolvedVisaProduct.resolve(product, override: nil)
        XCTAssertEqual(resolved.effectiveEligibility, .eligible)
        XCTAssertEqual(resolved.effectiveApplicationMode, .ours)
        XCTAssertEqual(resolved.effectiveGovFeeCents, 5000)
        XCTAssertEqual(resolved.effectiveProcessingTimeDays, 10)
        XCTAssertEqual(resolved.channel, .online)        // ours → online
    }

    func testResolveOverrideWins() throws {
        let product = try makeProduct(defaultEligibility: "eligible", applicationMode: "ours",
                                      govFeeCents: 5000, processingTimeDays: 10)
        let override = VisaProductEligibility(
            productID: product.id, passportIso2: "FR", eligibility: .notEligible,
            applicationMode: .external, notes: "EU citizen — free movement",
            govFeeCents: 0, serviceFeeCents: nil, processingTimeDays: 1
        )
        let resolved = ResolvedVisaProduct.resolve(product, override: override)
        XCTAssertEqual(resolved.effectiveEligibility, .notEligible)
        XCTAssertEqual(resolved.effectiveApplicationMode, .external)
        XCTAssertEqual(resolved.effectiveGovFeeCents, 0)
        XCTAssertEqual(resolved.effectiveProcessingTimeDays, 1)
        XCTAssertEqual(resolved.eligibilityNotes, "EU citizen — free movement")
        XCTAssertEqual(resolved.channel, .manual)        // external → manual
    }

    func testResolveOverrideFallsBackPerField() throws {
        // Override sets eligibility only; fees/mode fall back to the product.
        let product = try makeProduct(defaultEligibility: "eligible", applicationMode: "assisted",
                                      govFeeCents: 7500, processingTimeDays: 14)
        let override = VisaProductEligibility(
            productID: product.id, passportIso2: "GB", eligibility: .conditional,
            applicationMode: nil, notes: nil,
            govFeeCents: nil, serviceFeeCents: nil, processingTimeDays: nil
        )
        let resolved = ResolvedVisaProduct.resolve(product, override: override)
        XCTAssertEqual(resolved.effectiveEligibility, .conditional)
        XCTAssertEqual(resolved.effectiveApplicationMode, .assisted)   // fell back
        XCTAssertEqual(resolved.effectiveGovFeeCents, 7500)            // fell back
    }

    // MARK: - TopoJSON decoder

    func testTopoJSONDecodesPolygonWithTransform() throws {
        let atlas = try TopoJSON.decode(data: Data(Self.fixtureTopology.utf8))
        let testland = try XCTUnwrap(atlas.countries["840"])
        XCTAssertEqual(testland.name, "Testland")
        XCTAssertEqual(testland.rings.count, 1)
        let ring = testland.rings[0]
        XCTAssertEqual(ring.map(\.lon), [0, 10, 10])
        XCTAssertEqual(ring.map(\.lat), [0, 0, 10])
    }

    func testTopoJSONReversesNegativeArcIndex() throws {
        let atlas = try TopoJSON.decode(data: Data(Self.fixtureTopology.utf8))
        // "124" reuses arc 0 via index -1 (~(-1)=0) → reversed coordinates.
        let mirror = try XCTUnwrap(atlas.countries["124"])
        let ring = mirror.rings[0]
        XCTAssertEqual(ring.map(\.lon), [10, 10, 0])
        XCTAssertEqual(ring.map(\.lat), [10, 0, 0])
    }

    func testTopoJSONPadsShortNumericIDs() throws {
        let atlas = try TopoJSON.decode(data: Data(Self.fixtureTopology.utf8))
        XCTAssertNotNil(atlas.countries["004"])   // id "4" padded to "004"
    }

    // MARK: - Equal Earth projection

    func testEqualEarthOriginIsZero() {
        let p = EqualEarth.project(lonDeg: 0, latDeg: 0)
        XCTAssertEqual(Double(p.x), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(p.y), 0, accuracy: 1e-9)
    }

    func testEqualEarthMonotonic() {
        let east = EqualEarth.project(lonDeg: 90, latDeg: 0)
        let west = EqualEarth.project(lonDeg: -90, latDeg: 0)
        XCTAssertGreaterThan(east.x, west.x)            // east is right of west
        let north = EqualEarth.project(lonDeg: 0, latDeg: 60)
        let south = EqualEarth.project(lonDeg: 0, latDeg: -60)
        XCTAssertGreaterThan(north.y, south.y)          // north is up (plane y)
    }

    func testProjectionFitFlipsYToScreen() {
        let bounds = PlaneBounds(minX: -2, minY: -1, maxX: 2, maxY: 1)
        let fit = ProjectionFit.fitting(bounds: bounds, into: CGSize(width: 400, height: 200))
        let topPlane = fit.screen(CGPoint(x: 0, y: 1))     // max plane-y
        let bottomPlane = fit.screen(CGPoint(x: 0, y: -1))  // min plane-y
        XCTAssertLessThan(topPlane.y, bottomPlane.y)        // north maps to smaller screen-y
    }

    // MARK: - Country numeric padding

    func testPaddedNumeric() {
        XCTAssertEqual(country(numeric: "4").paddedNumeric, "004")
        XCTAssertEqual(country(numeric: "840").paddedNumeric, "840")
        XCTAssertEqual(country(numeric: "76").paddedNumeric, "076")
        XCTAssertNil(country(numeric: nil).paddedNumeric)
    }

    // MARK: - Fixtures

    private func req(_ passport: String, _ dest: String, _ status: VisaStatus) -> VisaRequirement {
        VisaRequirement(passportIso2: passport, destinationIso2: dest, status: status,
                        daysAllowed: nil, notes: nil)
    }

    private func country(numeric: String?) -> Country {
        Country(iso2: "XX", name: "X", region: nil, flagEmoji: nil, isPassport: nil,
                isoNumeric: numeric, slug: nil, coverageTier: nil)
    }

    private func makeProduct(defaultEligibility: String, applicationMode: String,
                             govFeeCents: Int?, processingTimeDays: Int?) throws -> VisaProduct {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "code": "test-product",
          "destination_iso2": "DE",
          "zone_code": null,
          "name": "Test Visa",
          "category": "tourist",
          "entry_type": "evisa",
          "application_mode": "\(applicationMode)",
          "default_eligibility": "\(defaultEligibility)",
          "max_stay_days": 90,
          "validity_days": 180,
          "processing_time_days": \(processingTimeDays.map(String.init) ?? "null"),
          "gov_fee_cents": \(govFeeCents.map(String.init) ?? "null"),
          "service_fee_cents": 2500,
          "currency": "USD",
          "summary": "A test product.",
          "more_info_url": null,
          "visa_type_code": "tourist",
          "sort_order": 1,
          "is_active": true,
          "attributes": {}
        }
        """
        return try JSONDecoder().decode(VisaProduct.self, from: Data(json.utf8))
    }

    /// scale/translate identity; arc 0 = (0,0)->(10,0)->(10,10). "840" uses it
    /// forward, "124" via index -1 (reversed), "4" exercises numeric padding.
    private static let fixtureTopology = """
    {
      "type": "Topology",
      "transform": { "scale": [1.0, 1.0], "translate": [0.0, 0.0] },
      "arcs": [ [[0,0],[10,0],[0,10]] ],
      "objects": { "countries": { "type": "GeometryCollection", "geometries": [
        { "type": "Polygon", "arcs": [[0]], "id": "840", "properties": { "name": "Testland" } },
        { "type": "Polygon", "arcs": [[-1]], "id": "124", "properties": { "name": "Mirrorland" } },
        { "type": "Polygon", "arcs": [[0]], "id": "4", "properties": { "name": "Shortland" } }
      ] } }
    }
    """
}

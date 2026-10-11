import XCTest
@testable import VisaPassage

/// IOS-02 logic: the passport preference, the dense passport rank, Explore's
/// status grouping and filter, and the rule-changes feed decoding.
@MainActor
final class HomeExploreTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "HomeExploreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: PassportPreference

    func testPreferenceClampsToTwoPrimaryFirst() {
        let pref = PassportPreference(defaults: freshDefaults())
        XCTAssertTrue(pref.add("ua"))
        XCTAssertTrue(pref.add("PL"))
        XCTAssertFalse(pref.add("DE"), "A third passport is refused")
        XCTAssertEqual(pref.passports, ["UA", "PL"])
        XCTAssertEqual(pref.primary, "UA")

        pref.makePrimary("PL")
        XCTAssertEqual(pref.passports, ["PL", "UA"])

        pref.toggle("PL")
        XCTAssertEqual(pref.passports, ["UA"])
    }

    func testPreferencePersistsAndCleans() {
        let defaults = freshDefaults()
        PassportPreference(defaults: defaults).set(["us", "US", "x", "CA", "GB"])
        XCTAssertEqual(defaults.string(forKey: PassportPreference.key), "US,CA")
        XCTAssertEqual(PassportPreference(defaults: defaults).passports, ["US", "CA"])
    }

    func testPreferenceMigratesLegacyKey() {
        let defaults = freshDefaults()
        defaults.set("de,fr,it", forKey: PassportPreference.legacyKey)
        let pref = PassportPreference(defaults: defaults)
        XCTAssertEqual(pref.passports, ["DE", "FR"])
        XCTAssertNil(defaults.string(forKey: PassportPreference.legacyKey))
        XCTAssertEqual(defaults.string(forKey: PassportPreference.key), "DE,FR")
    }

    // MARK: Passport ranking

    private func row(_ iso: String, _ score: Int, visaFree: Int = 0, known: Int = 200) -> PassportStrengthRow {
        PassportStrengthRow(passportIso2: iso, name: iso, visaFree: visaFree, visaOnArrival: score - visaFree,
                            evisa: 0, eta: 0, visaRequired: 0, noAdmission: 0, known: known, mobilityScore: score)
    }

    func testDenseRankSharesTiesAndSkipsSlugless() {
        let rows = [row("SG", 190), row("JP", 190), row("XX", 180), row("DE", 180), row("UA", 143, visaFree: 128)]
        let ranks = PassportRanking.rank(rows, slugged: ["SG", "JP", "DE", "UA"])
        XCTAssertEqual(ranks["SG"]?.rank, 1)
        XCTAssertEqual(ranks["JP"]?.rank, 1, "Ties share a rank")
        XCTAssertNil(ranks["XX"], "No slug, no rank")
        XCTAssertEqual(ranks["DE"]?.rank, 2, "Dense: no gap after a tie")
        XCTAssertEqual(ranks["UA"]?.rank, 3)
        XCTAssertEqual(ranks["UA"]?.totalRanked, 4)
        XCTAssertEqual(ranks["UA"]?.visaFree, 128)
        XCTAssertEqual(ranks["UA"]?.mobilityScore, 143)
    }

    func testPassportStrengthRowDecodes() throws {
        let json = #"[{"passport_iso2":"UA","name":"Ukraine","visa_free":128,"visa_on_arrival":15,"evisa":40,"eta":3,"visa_required":60,"no_admission":3,"known":249,"mobility_score":143}]"#
        let rows = try JSONDecoder().decode([PassportStrengthRow].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first?.mobilityScore, 143)
        XCTAssertEqual(rows.first?.eta, 3)
    }

    // MARK: Requirements fold

    private func req(_ passport: String, _ dest: String, _ status: VisaStatus, _ days: Int? = nil) -> VisaRequirement {
        VisaRequirement(passportIso2: passport, destinationIso2: dest, status: status, daysAllowed: days, notes: nil)
    }

    func testFoldKeepsStrongerStatusThenLongerStay() {
        let best = RequirementsStore.fold([
            req("UA", "TR", .visaFree, 90),
            req("PL", "TR", .evisa),
            req("UA", "GB", .visaRequired),
            req("PL", "GB", .eta),
            req("UA", "AL", .visaFree, 30),
            req("PL", "AL", .visaFree, 90),
        ])
        XCTAssertEqual(best["TR"]?.status, .visaFree)
        XCTAssertEqual(best["GB"]?.status, .eta)
        XCTAssertEqual(best["AL"]?.daysAllowed, 90)
    }

    func testEtaDecodesAndSortsAfterEvisa() throws {
        let status = try JSONDecoder().decode(VisaStatus.self, from: Data(#""eta""#.utf8))
        XCTAssertEqual(status, .eta)
        XCTAssertEqual(VisaStatus.best(.eta, .visaRequired), .eta)
        XCTAssertEqual(VisaStatus.best(.eta, .evisa), .evisa)
        XCTAssertEqual(VisaStatus.eta.hue, .blue)
    }

    // MARK: Explore grouping and filter

    private let countries = [
        Country(iso2: "AL", name: "Albania"),
        Country(iso2: "GB", name: "United Kingdom"),
        Country(iso2: "IN", name: "India"),
        Country(iso2: "TR", name: "Türkiye"),
        Country(iso2: "UA", name: "Ukraine"),
        Country(iso2: "AQ", name: "Antarctica"),
    ]

    private var best: [String: VisaRequirement] {
        [
            "AL": req("UA", "AL", .visaFree, 90),
            "TR": req("UA", "TR", .visaFree, 90),
            "GB": req("UA", "GB", .eta),
            "IN": req("UA", "IN", .evisa),
        ]
    }

    func testGroupsFollowPrecedenceWithNoDataLast() {
        let groups = DestinationGrouping.groups(countries: countries, best: best, filter: .all, query: "", excluding: ["UA"])
        XCTAssertEqual(groups.map(\.status), [.visaFree, .evisa, .eta, .unknown])
        XCTAssertEqual(groups.first?.entries.map(\.country.iso2), ["AL", "TR"])
        XCTAssertFalse(groups.flatMap(\.entries).contains { $0.country.iso2 == "UA" }, "Own passport is excluded")
    }

    func testEvisaFilterIncludesEta() {
        let groups = DestinationGrouping.groups(countries: countries, best: best, filter: .evisa, query: "", excluding: [])
        XCTAssertEqual(groups.map(\.status), [.evisa, .eta])
        XCTAssertTrue(ExploreFilter.evisa.matches(.eta))
        XCTAssertFalse(ExploreFilter.visaFree.matches(.visaOnArrival))
        XCTAssertTrue(ExploreFilter.all.matches(.unknown))
    }

    func testSearchMatchesNameOrCode() {
        let byName = DestinationGrouping.groups(countries: countries, best: best, filter: .all, query: "kingd", excluding: [])
        XCTAssertEqual(byName.flatMap(\.entries).map(\.country.iso2), ["GB"])
        let byCode = DestinationGrouping.groups(countries: countries, best: best, filter: .all, query: "tr", excluding: [])
        XCTAssertEqual(byCode.flatMap(\.entries).map(\.country.iso2), ["TR"])
    }

    // MARK: Rule changes

    func testPolicyChangeDecodesKindTranslationAndDate() throws {
        let json = #"""
        [{"id":"7b3c","destination_iso2":"TH","passport_iso2":null,"change_kind":"policy_relaxed",
          "title":"Thailand extends visa-free stays","summary":"60 days.","source_url":null,
          "effective_date":"2026-07-15","published_at":"2026-07-10T09:30:00.123+00:00",
          "translations":{"ru":{"title":"Таиланд продлил безвизовое пребывание"}}},
         {"id":"8c4d","destination_iso2":"GB","passport_iso2":"UA","change_kind":"something_new",
          "title":"T","summary":"S","source_url":null,"effective_date":null,
          "published_at":"2026-07-01T00:00:00+00:00","translations":"broken"}]
        """#
        let changes = try JSONDecoder().decode([PolicyChange].self, from: Data(json.utf8))
        XCTAssertEqual(changes[0].changeKind, .policyRelaxed)
        XCTAssertEqual(changes[0].changeKind.hue, .green)
        XCTAssertEqual(changes[0].localizedTitle(in: .ru), "Таиланд продлил безвизовое пребывание")
        XCTAssertEqual(changes[0].localizedTitle(in: .en), "Thailand extends visa-free stays")
        XCTAssertNotNil(changes[0].publishedDate)
        XCTAssertEqual(changes[1].changeKind, .unknown)
        XCTAssertNil(changes[1].translations, "A malformed blob is dropped, not fatal")
        XCTAssertNotNil(changes[1].publishedDate)
    }
}

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

    func testPreferenceClampsToFourPrimaryFirst() {
        let pref = PassportPreference(defaults: freshDefaults())
        XCTAssertTrue(pref.add("ua"))
        XCTAssertTrue(pref.add("PL"))
        XCTAssertTrue(pref.add("DE"))
        XCTAssertTrue(pref.add("IL"))
        XCTAssertTrue(pref.isFull)
        XCTAssertFalse(pref.add("FR"), "A fifth passport is refused")
        XCTAssertEqual(pref.passports, ["UA", "PL", "DE", "IL"])
        XCTAssertEqual(pref.primary, "UA")

        pref.makePrimary("DE")
        XCTAssertEqual(pref.passports, ["DE", "UA", "PL", "IL"])

        pref.toggle("DE")
        XCTAssertEqual(pref.passports, ["UA", "PL", "IL"])
        XCTAssertFalse(pref.isFull)
    }

    func testPreferencePersistsAndCleans() {
        let defaults = freshDefaults()
        PassportPreference(defaults: defaults).set(["us", "US", "x", "CA", "GB", "AU", "NZ"])
        XCTAssertEqual(defaults.string(forKey: PassportPreference.key), "US,CA,GB,AU")
        XCTAssertEqual(PassportPreference(defaults: defaults).passports, ["US", "CA", "GB", "AU"])
    }

    func testPreferenceMigratesLegacyKey() {
        let defaults = freshDefaults()
        defaults.set("de,fr,it,es,pt", forKey: PassportPreference.legacyKey)
        let pref = PassportPreference(defaults: defaults)
        XCTAssertEqual(pref.passports, ["DE", "FR", "IT", "ES"])
        XCTAssertNil(defaults.string(forKey: PassportPreference.legacyKey))
        XCTAssertEqual(defaults.string(forKey: PassportPreference.key), "DE,FR,IT,ES")
    }

    // MARK: Passport ranking (dense rank: PassportsTests)

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

    func testMapKeyCountsExcludeOwnPassport() {
        let counts = DestinationGrouping.counts(countries: countries, best: best, excluding: ["UA"])
        XCTAssertEqual(counts[.visaFree], 2)
        XCTAssertEqual(counts[.eta], 1)
        XCTAssertEqual(counts[.evisa], 1)
        XCTAssertEqual(counts[.unknown], 1, "Antarctica has no data; Ukraine is your passport")
        XCTAssertNil(counts[.visaRequired])
    }

    func testTablesShowFiveRowsUntilExpanded() {
        XCTAssertEqual(DestinationGrouping.visibleCount(total: 12, expanded: false), DestinationGrouping.rowLimit)
        XCTAssertEqual(DestinationGrouping.visibleCount(total: 12, expanded: true), 12)
        XCTAssertEqual(DestinationGrouping.visibleCount(total: 3, expanded: false), 3)
    }

    func testNoAdmissionFilter() {
        XCTAssertTrue(ExploreFilter.noAdmission.matches(.noAdmission))
        XCTAssertFalse(ExploreFilter.noAdmission.matches(.visaRequired))
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

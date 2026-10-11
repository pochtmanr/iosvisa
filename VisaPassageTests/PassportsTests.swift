import XCTest
@testable import VisaPassage

/// IOS-04: the dense-rank port, ranking search and filters, the passport page's
/// top stays, and the compare merge. Fixtures are real responses copied on
/// 2026-10-11: `passport_strength` and `countries` through PostgREST, and
/// `GET /api/passports?codes=DE,UA` from visapassage.com.
final class PassportsTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func realIndex() throws -> [PassportIndexRow] {
        let rows = try JSONDecoder().decode([PassportStrengthRow].self, from: fixture("passport-strength"))
        let countries = try JSONDecoder().decode([Country].self, from: fixture("countries-ranking"))
        return DenseRank.passportIndex(rows, countries: countries, locale: .en)
    }

    private func row(_ iso: String, _ score: Int, visaFree: Int = 0, known: Int = 200) -> PassportStrengthRow {
        PassportStrengthRow(passportIso2: iso, name: iso, visaFree: visaFree, visaOnArrival: score - visaFree,
                            evisa: 0, eta: 0, visaRequired: 0, noAdmission: 0, known: known, mobilityScore: score)
    }

    private func country(_ iso: String, slug: String?, region: String? = nil, name: String? = nil) -> Country {
        Country(iso2: iso, name: name ?? iso, region: region, slug: slug)
    }

    // MARK: Dense rank

    /// The numbers the web shows on /passports (checked live 2026-10-11).
    func testRealFixtureMatchesTheWeb() throws {
        let index = try realIndex()
        XCTAssertEqual(index.count, 237)
        let expected: [String: (rank: Int, mobility: Int, visaFree: Int)] = [
            "DE": (9, 170, 162),
            "UA": (31, 143, 128),
            "IN": (77, 57, 44),
            "NG": (79, 54, 44),
            "US": (11, 168, 153),
        ]
        for (iso, want) in expected {
            let got = try XCTUnwrap(index.first { $0.iso2 == iso }, iso)
            XCTAssertEqual(got.rank, want.rank, "\(iso) rank")
            XCTAssertEqual(got.mobilityScore, want.mobility, "\(iso) mobility")
            XCTAssertEqual(got.visaFree, want.visaFree, "\(iso) visa-free")
        }
    }

    func testRealFixtureRanksAreDense() throws {
        let index = try realIndex()
        XCTAssertEqual(index.first?.rank, 1)
        for (a, b) in zip(index, index.dropFirst()) {
            if a.mobilityScore == b.mobilityScore {
                XCTAssertEqual(a.rank, b.rank, "ties share a rank")
            } else {
                XCTAssertGreaterThan(a.mobilityScore, b.mobilityScore, "input order is kept")
                XCTAssertEqual(b.rank, a.rank + 1, "dense: no gaps")
            }
        }
    }

    func testDenseRankSharesTiesAndSkipsSlugless() {
        let rows = [row("SG", 190), row("JP", 190), row("XX", 180), row("DE", 180), row("UA", 143, visaFree: 128)]
        let countries = [country("SG", slug: "singapore"), country("JP", slug: "japan"), country("XX", slug: nil),
                         country("DE", slug: "germany", region: "Europe"), country("UA", slug: "ukraine")]
        let index = DenseRank.passportIndex(rows, countries: countries, locale: .en)
        let rank = Dictionary(uniqueKeysWithValues: index.map { ($0.iso2, $0.rank) })
        XCTAssertEqual(rank["SG"], 1)
        XCTAssertEqual(rank["JP"], 1, "Ties share a rank")
        XCTAssertNil(rank["XX"], "No slug, no rank")
        XCTAssertEqual(rank["DE"], 2, "Dense: no gap after a tie")
        XCTAssertEqual(rank["UA"], 3)
        XCTAssertEqual(index.count, 4)
        XCTAssertEqual(index.first { $0.iso2 == "DE" }?.region, "Europe")
        XCTAssertEqual(index.first { $0.iso2 == "UA" }?.visaFree, 128)
    }

    func testSluglessPassportDoesNotTakeARank() {
        // A slugless passport with its own score between two others must not
        // consume a rank number (the web skips it before counting).
        let rows = [row("AA", 200), row("XX", 190), row("BB", 180)]
        let index = DenseRank.passportIndex(rows, countries: [country("AA", slug: "a"), country("BB", slug: "b")], locale: .en)
        XCTAssertEqual(index.map(\.rank), [1, 2])
    }

    func testStoreRankReportsTotal() throws {
        let index = try realIndex()
        let ua = try XCTUnwrap(index.first { $0.iso2 == "UA" })
        let rank = PassportRank(ua, totalRanked: index.count)
        XCTAssertEqual(rank.rank, 31)
        XCTAssertEqual(rank.totalRanked, 237)
        XCTAssertEqual(rank.mobilityScore, 143)
    }

    // MARK: Search and regions

    func testSearchIsAccentAndCaseInsensitiveOrExactISO() {
        let ci = PassportIndexRow(iso2: "CI", name: "Côte d’Ivoire", englishName: "Côte d’Ivoire", slug: "cote-divoire",
                                  region: "Africa", rank: 1, mobilityScore: 1, known: 1,
                                  counts: PassportCounts(visaFree: 0, visaOnArrival: 0, evisa: 0, eta: 0, visaRequired: 0, noAdmission: 0))
        XCTAssertTrue(PassportFilters.matches(ci, query: "cote"))
        XCTAssertTrue(PassportFilters.matches(ci, query: "  CÔTE "))
        XCTAssertTrue(PassportFilters.matches(ci, query: "ci"), "exact ISO2")
        XCTAssertFalse(PassportFilters.matches(ci, query: "xy"))
        XCTAssertTrue(PassportFilters.matches(ci, query: ""))

        var de = ci
        de.iso2 = "DE"; de.name = "Германия"; de.englishName = "Germany"
        XCTAssertTrue(PassportFilters.matches(de, query: "герм"))
        XCTAssertTrue(PassportFilters.matches(de, query: "germany"), "English name also matches")
    }

    func testRegionFilterKeepsRankOrder() throws {
        let index = try realIndex()
        let europe = PassportFilters.filter(index, region: "Europe", query: "")
        XCTAssertFalse(europe.isEmpty)
        XCTAssertTrue(europe.allSatisfy { $0.region == "Europe" })
        XCTAssertEqual(europe.map(\.rank), europe.map(\.rank).sorted())
        XCTAssertTrue(europe.contains { $0.iso2 == "DE" })
        XCTAssertEqual(PassportFilters.regions(in: index), ["Africa", "Americas", "Asia", "Europe", "Oceania"])
        XCTAssertEqual(PassportFilters.filter(index, region: nil, query: "ukr").map(\.iso2), ["UA"])
    }

    // MARK: Passport page

    func testTopVisaFreeLongestStayThenName() {
        func req(_ dest: String, _ status: VisaStatus, _ days: Int?) -> VisaRequirement {
            VisaRequirement(passportIso2: "UA", destinationIso2: dest, status: status, daysAllowed: days, notes: nil)
        }
        let rows = [req("AA", .visaFree, 30), req("BB", .visaFree, 90), req("CC", .visaFree, 90),
                    req("DD", .visaOnArrival, 360), req("EE", .visaFree, nil), req("ZZ", .visaFree, 999)]
        let names = ["AA": "Alpha", "BB": "Charlie", "CC": "Bravo", "DD": "Delta", "EE": "Echo"]
        let stays = PassportFilters.topVisaFree(rows) { names[$0] }
        XCTAssertEqual(stays.map(\.iso2), ["CC", "BB", "AA", "EE"], "days desc, then A–Z; non visa-free and unknown countries dropped")
        XCTAssertEqual(PassportFilters.topVisaFree(rows, name: { names[$0] }, limit: 2).count, 2)
    }

    // MARK: Compare

    func testCompareFixtureDecodesAndMatchesTheWeb() throws {
        let body = try JSONDecoder.visaPassage.decode(CompareResponse.self, from: fixture("compare-de-ua"))
        XCTAssertEqual(body.passports.map(\.iso2), ["DE", "UA"])
        XCTAssertEqual(body.passports.map(\.rank), [9, 31])
        XCTAssertEqual(body.passports.map(\.mobilityScore), [170, 143])

        let c = PassportComparison(body.passports)
        XCTAssertGreaterThanOrEqual(c.combinedMobility, c.bestSingle)
        XCTAssertEqual(c.bestSingle, 170)
        XCTAssertEqual(c.leads.values.reduce(0, +), c.combinedMobility)
        XCTAssertEqual(c.counts.values.reduce(0, +), c.merged.count)
        // Every differing row really differs, and is sorted easiest first.
        XCTAssertTrue(c.differing.allSatisfy { Set($0.statuses).count > 1 })
        let order = c.differing.map { VisaStatus.precedence.firstIndex(of: $0.best) ?? 99 }
        XCTAssertEqual(order, order.sorted())
    }

    func testMergeTieKeepsFirstPassportAndBetterStatusWins() {
        func p(_ iso: String, _ reqs: [(String, VisaStatus)]) -> ComparePassport {
            ComparePassport(iso2: iso, name: iso, rank: 1, mobilityScore: 0, requirements: reqs.map {
                .init(destinationIso2: $0.0, name: $0.0, status: $0.1, daysAllowed: nil)
            })
        }
        let a = p("AA", [("X1", .visaFree), ("X2", .visaRequired), ("X3", .evisa)])
        let b = p("BB", [("X1", .visaFree), ("X2", .visaOnArrival), ("X3", .evisa), ("X4", .visaFree)])
        let c = PassportComparison([a, b])
        let via = Dictionary(uniqueKeysWithValues: c.merged.map { ($0.destinationIso2, $0.viaPassport) })
        XCTAssertEqual(via["X1"], "AA", "tie keeps the first passport")
        XCTAssertEqual(via["X2"], "BB", "strictly better status wins")
        XCTAssertEqual(c.merged.map(\.destinationIso2), ["X1", "X2", "X3", "X4"], "first-seen order")
        XCTAssertEqual(c.combinedMobility, 3)
        XCTAssertEqual(c.leads["AA"], 1)
        XCTAssertEqual(c.leads["BB"], 2)
        XCTAssertEqual(c.differing.map(\.iso2), ["X2"], "X4 lacks AA data; X1/X3 are equal")
        XCTAssertEqual(c.sameCount, 2)
    }

    func testCompareCodesNormalizeLikeTheRoute() {
        XCTAssertEqual(PassportRankingRepository.normalize(["ua", "DE", "de", "x", "US", "IN", "NG"]), ["DE", "IN", "NG", "UA"])
        let url = PassportRankingRepository.compareURL(base: URL(string: "https://visapassage.com")!, codes: ["ua", "de"])
        XCTAssertEqual(url.absoluteString, "https://visapassage.com/api/passports?codes=DE,UA")
    }

    // MARK: Redesign (sort, scoreboard, regions, summary)

    func testSortMostVisaFreeBreaksTiesByRankAndNameIsAlphabetical() throws {
        let index = try realIndex()
        let byVisaFree = PassportFilters.sort(index, by: .visaFree)
        XCTAssertEqual(byVisaFree.count, index.count)
        for (a, b) in zip(byVisaFree, byVisaFree.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.visaFree, b.visaFree)
            if a.visaFree == b.visaFree { XCTAssertLessThanOrEqual(a.rank, b.rank, "ties: rank order") }
        }
        let byName = PassportFilters.sort(index, by: .name).map(\.name)
        XCTAssertEqual(byName, byName.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertEqual(PassportFilters.sort(index, by: .rank), index, "rank keeps the server order")
    }

    func testScoreboardWinners() {
        XCTAssertEqual(PassportComparison.winners([9, 31], lowerIsBetter: true), [0], "rank: lower wins")
        XCTAssertEqual(PassportComparison.winners([170, 143], lowerIsBetter: false), [0])
        XCTAssertEqual(PassportComparison.winners([13, 29], lowerIsBetter: true), [0], "visa required: fewer wins")
        XCTAssertEqual(PassportComparison.winners([5, 5, 2], lowerIsBetter: false), [0, 1], "shared lead")
        XCTAssertEqual(PassportComparison.winners([4, 4], lowerIsBetter: false), [], "a level row marks no one")
    }

    func testRegionTalliesAndEasierGroups() {
        func p(_ iso: String, _ reqs: [(String, VisaStatus)]) -> ComparePassport {
            ComparePassport(iso2: iso, name: iso, rank: 1, mobilityScore: 0, requirements: reqs.map {
                .init(destinationIso2: $0.0, name: $0.0, status: $0.1, daysAllowed: 90)
            })
        }
        let a = p("AA", [("X1", .visaFree), ("X2", .visaRequired), ("X3", .visaOnArrival), ("X5", .evisa)])
        let b = p("BB", [("X1", .visaFree), ("X2", .visaOnArrival), ("X3", .visaRequired), ("X4", .visaFree), ("X5", .evisa)])
        let c = PassportComparison([a, b])
        let region = ["X1": "Europe", "X2": "Europe", "X3": "Asia", "X4": "Asia", "X5": "Asia"]
        let tallies = Dictionary(uniqueKeysWithValues: c.regionTallies { region[$0] }.map { ($0.region, $0) })
        XCTAssertEqual(tallies["Europe"]?.counts, [1, 2])
        XCTAssertEqual(tallies["Europe"]?.total, 2)
        XCTAssertEqual(tallies["Asia"]?.counts, [1, 0], "X4 lacks AA data, so it is left out")
        XCTAssertEqual(tallies["Asia"]?.total, 2)
        XCTAssertEqual(tallies["Africa"]?.total, 0)
        XCTAssertEqual(c.easier(with: 0).map(\.iso2), ["X3"])
        XCTAssertEqual(c.easier(with: 1).map(\.iso2), ["X2"])
        XCTAssertEqual(c.differing.first?.days, [90, 90])
    }

    func testSummaryFixtureDecodes() throws {
        let s = try JSONDecoder.visaPassage.decode(PassportSummary.self, from: fixture("summary-de"))
        XCTAssertEqual(s.iso2, "DE")
        XCTAssertEqual(s.rank, 9, "same rank as the ported dense rank")
        XCTAssertEqual(s.totalRanked, 237)
        XCTAssertEqual(s.mobilityScore, 170)
        XCTAssertLessThanOrEqual(s.topVisaFree.count, PassportFilters.topVisaFreeLimit)
        XCTAssertEqual(s.topVisaFree.first?.iso2, "GE")
        XCTAssertLessThanOrEqual(s.combos.count, 5)
        XCTAssertTrue(s.combos.allSatisfy { $0.uplift > 0 && $0.combinedMobility == 170 + $0.uplift })
        let url = PassportRankingRepository.summaryURL(base: URL(string: "https://visapassage.com")!, slug: "germany", locale: .ru)
        XCTAssertEqual(url.absoluteString, "https://visapassage.com/api/passports/germany/summary?locale=ru")
    }
}

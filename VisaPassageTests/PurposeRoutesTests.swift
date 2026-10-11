import XCTest
@testable import VisaPassage

/// The purpose cards' logic, matched 1:1 with the web: the purpose order and
/// goals (`purposes.ts`), the route fold (`/api/visa-checker/purposes`), the
/// rights parser (`parseRights`) and the route map model (`useCheckerState`,
/// `DestinationPanel`).
final class PurposeRoutesTests: XCTestCase {

    // MARK: Purpose

    func testPurposeOrderMatchesWeb() {
        XCTAssertEqual(Purpose.allCases.map(\.rawValue),
                       ["travel", "study", "work", "remote", "immigrate", "invest", "family"])
        XCTAssertFalse(Purpose.travel.isRoute)
        XCTAssertTrue(Purpose.allCases.dropFirst().allSatisfy(\.isRoute))
        XCTAssertEqual(Purpose.family.typeCodes, ["family_reunification", "spouse_partner", "dependent_relative"])
    }

    func testPurposeFromGoalsTakesTheFirstKnownGoal() {
        XCTAssertNil(Purpose.fromGoals(nil))
        XCTAssertNil(Purpose.fromGoals(["something_else"]))
        XCTAssertEqual(Purpose.fromGoals(["other", "work_abroad", "study"]), .work)
        XCTAssertEqual(Purpose.fromGoals(["invest"]), .invest)
    }

    // MARK: Rights

    func testParseRightsSkipsDeniedAndReadsNumbers() {
        let rights = CheckerRouteRight.parse([
            "work_rights": .object(["allowed": .bool(true), "hours_per_week": .number(20)]),
            "study_rights": .bool(false),
            "path_to_residency": .object(["years": .number(5)]),
            "family_inclusion": .object(["allowed": .bool(false)]),
        ])
        XCTAssertEqual(rights, [
            CheckerRouteRight(key: .work, hours: 20),
            CheckerRouteRight(key: .residency, years: 5),
        ])
        XCTAssertEqual(CheckerRouteRight.parse(["study_rights": .string("Part-time")]),
                       [CheckerRouteRight(key: .study)])
    }

    // MARK: Fold

    private func product(_ code: String, type: String, dest: String? = nil, zone: String? = nil,
                         sort: Int? = 0, eligibility: VisaEligibility = .eligible,
                         id: UUID = UUID()) -> PurposeRoutesRepository.ProductRow {
        PurposeRoutesRepository.ProductRow(
            id: id, code: code, name: code.uppercased(), visaTypeCode: type,
            destinationIso2: dest, zoneCode: zone, maxStayDays: nil, processingTimeDays: nil,
            defaultEligibility: eligibility, sortOrder: sort,
            translations: ["ru": ["name": "ru-\(code)"]], attributes: nil)
    }

    func testFoldExpandsZonesOrdersByTypeAndDedupes() {
        let schengen = product("schengen_student", type: "student", zone: "SCHENGEN")
        let deLanguage = product("de_language", type: "language_study", dest: "de")
        let deStudent = product("de_student", type: "student", dest: "DE", sort: 2)
        let frStudent = product("fr_student", type: "student", dest: "FR")
        let result = PurposeRoutesRepository.fold(
            purpose: .study,
            products: [deLanguage, deStudent, schengen, frStudent],
            types: [
                .init(code: "language_study", name: "Language study", translations: nil),
                .init(code: "student", name: "Student", translations: ["ru": ["name": "Студент"]]),
                .init(code: "exchange_program", name: "Exchange", translations: nil),
            ],
            members: [
                .init(zoneCode: "SCHENGEN", memberIso2: "de"),
                .init(zoneCode: "SCHENGEN", memberIso2: "FR"),
            ],
            overrides: [],
            locale: .en
        )
        // Student (type order 0) before language study (1); inside a type, sort_order.
        XCTAssertEqual(result.destinations["DE"]?.map(\.code), ["schengen_student", "de_student", "de_language"])
        XCTAssertEqual(result.destinations["FR"]?.map(\.code), ["schengen_student", "fr_student"])
        // Only the types with a route, in purpose order.
        XCTAssertEqual(result.types.map(\.code), ["student", "language_study"])
        XCTAssertEqual(result.typeName("student"), "Student")
    }

    func testFoldLocalizesAndAppliesBestOverride() {
        let id = UUID()
        let row = product("x", type: "student", dest: "IT", eligibility: .notEligible, id: id)
        let result = PurposeRoutesRepository.fold(
            purpose: .study, products: [row],
            types: [.init(code: "student", name: "Student", translations: ["ru": ["name": "Студент"]])],
            members: [],
            overrides: [
                .init(productId: id, eligibility: .conditional),
                .init(productId: id, eligibility: .eligible),
                .init(productId: id, eligibility: .notEligible),
            ],
            locale: .ru
        )
        let route = result.destinations["IT"]?.first
        XCTAssertEqual(route?.eligibility, .eligible, "The best override across passports wins")
        XCTAssertEqual(route?.name, "ru-x")
        XCTAssertEqual(result.typeName("student"), "Студент")
    }

    func testParsePassportsMatchesWeb() {
        XCTAssertEqual(PurposeRoutesRepository.parsePassports(["us", "GB", "us", "x1", "ABC"]), ["GB", "US"])
        XCTAssertEqual(PurposeRoutesRepository.parsePassports(["a", "AA", "BB", "CC", "DD", "EE", "FF"]),
                       ["AA", "BB", "CC", "DD", "EE"])
    }

    // MARK: Route map model

    private func route(_ code: String, _ type: String) -> CheckerRoute {
        CheckerRoute(id: UUID(), code: code, name: code, visaTypeCode: type,
                     maxStayDays: nil, processingTimeDays: nil, eligibility: .eligible, rights: [])
    }

    private var sample: CheckerRoutes {
        CheckerRoutes(
            purpose: .work,
            types: [.init(code: "skilled_work", name: "Skilled"), .init(code: "talent", name: "Talent")],
            destinations: [
                "DE": [route("a", "skilled_work"), route("b", "talent")],
                "PL": [route("c", "skilled_work")],
                "UA": [route("d", "talent")],
                "NO": [],
            ]
        )
    }

    private let countries = ["DE", "PL", "UA", "NO", "IT"].map { Country(iso2: $0, name: $0) }

    func testDepthBucketsSkipHomeAndCountNone() {
        let model = RouteMapModel(routes: sample, home: ["UA"], typeFilter: nil)
        let depth = model.depth(countries: countries)
        XCTAssertEqual(depth.buckets, [1, 1, 0], "PL has one type, DE two; UA is home")
        XCTAssertEqual(depth.none, 2, "NO (empty list) and IT")
        XCTAssertEqual(model.countsByType, ["skilled_work": 2, "talent": 2])
    }

    func testTypeFilterNarrowsListButNotNoRoute() {
        let model = RouteMapModel(routes: sample, home: [], typeFilter: "talent")
        let groups = model.groups(countries: countries, query: "")
        XCTAssertEqual(groups.routes.map(\.id), ["DE", "UA"])
        // PL is hidden by the chip, not "no route": it leaves the list.
        XCTAssertEqual(groups.none.map(\.id), ["IT", "NO"])
        XCTAssertEqual(model.fills(purpose: .work).count, 3, "Every country with routes keeps a fill")
    }

    func testGroupsSortByRouteCountThenName() {
        let model = RouteMapModel(routes: sample, home: [], typeFilter: nil)
        XCTAssertEqual(model.groups(countries: countries, query: "").routes.map(\.id), ["DE", "PL", "UA"])
        XCTAssertEqual(model.groups(countries: countries, query: "pl").routes.map(\.id), ["PL"])
    }
}

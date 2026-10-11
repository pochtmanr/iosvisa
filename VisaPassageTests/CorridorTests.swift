import XCTest
@testable import VisaPassage

/// The corridor port (`Corridor`) against a trimmed copy of the live
/// `GET /api/destinations/germany?passports=UA&locale=en` response.
final class CorridorTests: XCTestCase {
    private func routes() throws -> DestinationRoutesView {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "destination-de-ua", withExtension: "json"))
        return try JSONDecoder.visaPassage.decode(DestinationRoutesView.self, from: Data(contentsOf: url))
    }

    private func corridor(_ status: VisaStatus, days: Int?, notes: String? = nil) throws -> Corridor {
        let view = try routes()
        return Corridor(
            from: Country(iso2: "UA", name: "Ukraine", slug: "ukraine"),
            to: view.country,
            verdict: VisaRequirement(passportIso2: "UA", destinationIso2: "DE", status: status, daysAllowed: days, notes: notes),
            routes: view,
            locale: .en
        )
    }

    // MARK: Decoding

    func testDecodesDestinationRoutes() throws {
        let view = try routes()
        XCTAssertEqual(view.country.iso2, "DE")
        XCTAssertEqual(view.country.slug, "germany")
        XCTAssertEqual(view.groups.first?.group, .visitor)
        XCTAssertEqual(view.visitorStatuses.first?.status, .visaFree)
        XCTAssertEqual(view.visitorStatuses.first?.daysAllowed, 90)
        let etias = try XCTUnwrap(view.group(.visitor)?.products.first { $0.entryType == .eta })
        XCTAssertEqual(etias.govFee, 700)
        XCTAssertEqual(etias.currency, "EUR")
        XCTAssertEqual(etias.zoneCode, "schengen")
        XCTAssertTrue(view.groups.contains { $0.routes.contains { $0.tier == .availability } })
        XCTAssertTrue(view.groups.contains { $0.routes.contains { $0.tier == .unknown } })
    }

    func testRoundTripsThroughTheCacheEncoding() throws {
        let view = try routes()
        let data = try JSONEncoder().encode(view)
        XCTAssertEqual(try JSONDecoder().decode(DestinationRoutesView.self, from: data), view)
    }

    // MARK: Visa-free (UA → DE)

    func testVisaFreeHasNoApplicationProduct() throws {
        let c = try corridor(.visaFree, days: 90)
        XCTAssertNil(c.best)
        XCTAssertEqual(c.etaProduct?.entryType, .eta)
        XCTAssertTrue(c.visitorExtras.isEmpty)
        XCTAssertTrue(c.documents.isEmpty)
        XCTAssertEqual(c.daysAllowed, 90)
    }

    func testVisaFreeSchengenTags() throws {
        let c = try corridor(.visaFree, days: 90)
        XCTAssertEqual(c.tags, [.zone("schengen"), .rule90180, .etaPlanned("ETIAS travel authorisation")])
    }

    func testBiometricNoteAddsTag() throws {
        let c = try corridor(.visaFree, days: 90, notes: "Visa-free with biometric passport")
        XCTAssertTrue(c.tags.contains(.biometricPassport))
        XCTAssertEqual(c.borderNotes.map(\.kind), [.biometric, .rule, .eta, .border])
    }

    func testVisaFreeFacts() throws {
        let facts = try corridor(.visaFree, days: 90).facts
        XCTAssertEqual(facts.map(\.kind), [.stay, .fee, .processing, .routes])
        XCTAssertEqual(facts[0].value, "90 days")
        XCTAssertEqual(facts[0].hint, "in any 180 days")
        XCTAssertEqual(facts[1].value, "None")
        XCTAssertEqual(facts[2].value, "Not needed")
    }

    func testVisaFreeFAQ() throws {
        let faq = try corridor(.visaFree, days: 90).faq
        XCTAssertEqual(faq.count, 3)
        XCTAssertEqual(faq[0].question, "Do citizens of Ukraine need a visa to visit Germany?")
        XCTAssertTrue(faq[0].answer.hasPrefix("No — citizens of Ukraine can typically visit Germany visa-free for stays of up to 90 days."))
        XCTAssertTrue(faq[1].answer.hasPrefix("Up to 90 days per visit under the visa-free arrangement"))
        XCTAssertEqual(faq[2].question, "Can citizens of Ukraine work or study in Germany?")
    }

    // MARK: Visa required (the same routes, a consular verdict)

    func testVisaRequiredPicksLowestSortConsularProduct() throws {
        let c = try corridor(.visaRequired, days: nil)
        let best = try XCTUnwrap(c.best)
        XCTAssertEqual(best.entryType, .consular)
        XCTAssertTrue(best.name.contains("tourism"))
        XCTAssertEqual(c.daysAllowed, best.maxStayDays)
        XCTAssertNil(c.etaProduct)
        XCTAssertFalse(c.visitorExtras.contains { $0.id == best.id || $0.entryType == .eta })
        XCTAssertEqual(c.visitorExtras.count, 2)
    }

    func testVisaRequiredChecklistAndTags() throws {
        let c = try corridor(.visaRequired, days: nil)
        XCTAssertEqual(c.documents.count, 8)
        XCTAssertEqual(c.documents.map(\.sortOrder), c.documents.map(\.sortOrder).sorted())
        XCTAssertTrue(c.borderNotes.isEmpty)
        XCTAssertEqual(c.tags, [.zone("schengen"), .applyConsulate])
        XCTAssertNil(c.applyURL, "Only eVisa / eTA products get the Apply online pill")
    }

    func testVisaRequiredFactsAndFAQ() throws {
        let c = try corridor(.visaRequired, days: nil)
        let fee = try XCTUnwrap(c.facts.first { $0.kind == .fee })
        XCTAssertEqual(fee.value, "€90")
        XCTAssertEqual(c.facts.first { $0.kind == .processing }?.value, "~15 days")
        XCTAssertEqual(c.facts.last?.kind, .validity)
        let apply = try XCTUnwrap(c.faq.first { $0.question.contains("apply for the Germany visa") })
        XCTAssertTrue(apply.answer.contains("The government fee is €90."))
        XCTAssertTrue(apply.answer.contains("Processing typically takes 15 days."))
    }

    func testEVisaWithoutAMatchingProductHasNoBest() throws {
        XCTAssertNil(try corridor(.evisa, days: 30).best)
    }

    func testNoAdmissionHidesStay() throws {
        let c = try corridor(.noAdmission, days: 30)
        XCTAssertNil(c.facts.first { $0.kind == .stay }?.value)
        XCTAssertFalse(c.faq.contains { $0.question.hasPrefix("How long") })
    }

    func testWebURL() throws {
        XCTAssertEqual(try corridor(.visaFree, days: 90).webURL?.absoluteString,
                       "https://visapassage.com/travel/ukraine/germany")
    }

    // MARK: Guides

    func testGuideResolutionOrder() {
        let req = DocumentRequirement(id: UUID(), productID: UUID(), label: "Police certificate", required: true,
                                      sortOrder: 1, kind: "police_certificate")
        let generic = DocumentGuideRow(kind: "police_certificate", countryIso2: "XX", howToObtain: "Generic")
        let ukrainian = DocumentGuideRow(kind: "police_certificate", countryIso2: "UA", howToObtain: "Diia")
        XCTAssertEqual(DocumentGuide.resolve(req, passport: "UA", guides: [generic, ukrainian])?.howToObtain, "Diia")
        XCTAssertEqual(DocumentGuide.resolve(req, passport: "IN", guides: [generic, ukrainian])?.howToObtain, "Generic")

        var own = req
        own.howToObtain = "Ask the consulate"
        let override = DocumentGuide.resolve(own, passport: "UA", guides: [ukrainian])
        XCTAssertEqual(override?.howToObtain, "Ask the consulate")
        XCTAssertNil(override?.source)

        var kindless = req
        kindless.kind = nil
        XCTAssertNil(DocumentGuide.resolve(kindless, passport: "UA", guides: [generic]))
    }

    // MARK: Formatting

    func testMoneyCompact() {
        XCTAssertEqual(Money.compact(cents: 9000, currency: "EUR", locale: .en), "€90")
        XCTAssertEqual(Money.compact(cents: 1050, currency: "USD", locale: .en), "$10.50")
        XCTAssertNil(Money.compact(cents: nil, currency: "EUR", locale: .en))
    }

    func testNameInProse() {
        XCTAssertEqual(CorridorText.nameInProse("United States", locale: .en), "the United States")
        XCTAssertEqual(CorridorText.nameInProse("United States", locale: .ru), "United States")
        XCTAssertEqual(CorridorText.nameInProse("Germany", locale: .en), "Germany")
    }

    func testRoutesKeyNormalisesPassports() {
        XCTAssertEqual(CorridorRepository.routesKey(slug: "Germany", passports: ["us", "UA", "US"], locale: .ru),
                       "destination-routes:v1:germany:UA,US:ru")
    }
}

private extension DocumentRequirement {
    init(id: UUID, productID: UUID, label: String, required: Bool, sortOrder: Int, kind: String?) {
        self.init(id: id, productID: productID, label: label, description: nil, required: required,
                  sortOrder: sortOrder, kind: kind, howToObtain: nil, issuingAuthority: nil, obtainURL: nil,
                  typicalCost: nil, typicalTime: nil)
    }
}

private extension DocumentGuideRow {
    init(kind: String, countryIso2: String, howToObtain: String) {
        self.init(kind: kind, countryIso2: countryIso2, howToObtain: howToObtain, issuingAuthority: nil,
                  obtainURL: nil, typicalCost: nil, typicalTime: nil, sourceURL: nil, lastVerifiedAt: nil, confidence: nil)
    }
}

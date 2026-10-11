import XCTest
@testable import VisaPassage

/// Pure-logic M3 tests: the readiness gate + step states, the vault→
/// `applicant_details` prefill mapping, profile completeness, status→bucket
/// grouping, and `VisaApplication` / `ApplicantDetails` round-tripping (unknown
/// jsonb keys preserved). All headless — no network or running app.
final class ApplicationsM3Tests: XCTestCase {

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func completeProfile() throws -> Profile {
        try decode(Profile.self, """
        {"id":"11111111-1111-1111-1111-111111111111",
         "legal_first_name":"Ada","legal_last_name":"Lovelace",
         "date_of_birth":"1990-05-10","phone":"+44 20 7946 0000",
         "residential_address":{"city":"London"}}
        """)
    }

    private func confirmedDetails() -> ApplicantDetails {
        var d = ApplicantDetails()
        d.setFlag(.detailsConfirmed, true)
        d.setFlag(.documentsAcknowledged, true)
        return d
    }

    // MARK: - Readiness

    func testReadyWhenAllGatesPass() throws {
        let r = ApplicationReadiness.evaluate(
            status: .draft, details: confirmedDetails(), category: .tourist,
            checklist: [], profile: try completeProfile(), passportCount: 1)
        XCTAssertTrue(r.profileComplete)
        XCTAssertTrue(r.ready)
        XCTAssertFalse(r.state(.payment).blocked)
        XCTAssertTrue(r.state(.details).done)
        XCTAssertTrue(r.state(.documents).done)
    }

    func testNotReadyWhenDocumentsUnacknowledged() throws {
        var details = ApplicantDetails()
        details.setFlag(.detailsConfirmed, true)
        let r = ApplicationReadiness.evaluate(
            status: .draft, details: details, category: .tourist,
            checklist: [], profile: try completeProfile(), passportCount: 1)
        XCTAssertFalse(r.documentsAcknowledged)
        XCTAssertFalse(r.ready)
        XCTAssertTrue(r.state(.payment).blocked)
        XCTAssertFalse(r.state(.documents).done)
    }

    func testNotReadyWhenProfileIncomplete() throws {
        let r = ApplicationReadiness.evaluate(
            status: .draft, details: confirmedDetails(), category: .tourist,
            checklist: [], profile: try completeProfile(), passportCount: 0) // no passport
        XCTAssertFalse(r.profileComplete)
        XCTAssertFalse(r.ready)
    }

    func testWorkCategoryRequiresEmployment() throws {
        let profile = try completeProfile()
        let without = ApplicationReadiness.evaluate(
            status: .draft, details: confirmedDetails(), category: .work,
            checklist: [], profile: profile, passportCount: 1, employmentCount: 0)
        XCTAssertFalse(without.profileComplete)

        let with = ApplicationReadiness.evaluate(
            status: .draft, details: confirmedDetails(), category: .work,
            checklist: [], profile: profile, passportCount: 1, employmentCount: 1)
        XCTAssertTrue(with.profileComplete)
        XCTAssertTrue(with.ready)
    }

    func testPostPaymentImpliesEarlierStepsDoneAndDefaultsToTracking() throws {
        let r = ApplicationReadiness.evaluate(
            status: .paid, details: ApplicantDetails(), category: .tourist,
            checklist: [], profile: try completeProfile(), passportCount: 1)
        XCTAssertTrue(r.detailsConfirmed)        // forced by post-payment
        XCTAssertTrue(r.documentsAcknowledged)
        XCTAssertTrue(r.state(.payment).done)
        XCTAssertEqual(ApplicationReadiness.defaultStep(status: .paid, readiness: r), .tracking)
    }

    func testRequiredDocsCounts() throws {
        let checklist = [
            ChecklistItem(requirement: requirement(required: true), status: .missing),
            ChecklistItem(requirement: requirement(required: true), status: .accepted),
            ChecklistItem(requirement: requirement(required: false), status: .uploaded),
        ]
        let r = ApplicationReadiness.evaluate(
            status: .draft, details: confirmedDetails(), category: .tourist,
            checklist: checklist, profile: try completeProfile(), passportCount: 1)
        XCTAssertEqual(r.requiredDocsTotal, 2)
        XCTAssertEqual(r.requiredDocsDone, 1)
        XCTAssertEqual(r.docsTotal, 3)
        XCTAssertEqual(r.docsDone, 2)
    }

    private func requirement(required: Bool) -> DocumentRequirement {
        DocumentRequirement(
            id: UUID(), productID: UUID(), label: "Passport bio page",
            description: nil, required: required, sortOrder: 0, kind: nil,
            howToObtain: nil, issuingAuthority: nil, obtainURL: nil,
            typicalCost: nil, typicalTime: nil)
    }

    // MARK: - Prefill mapping

    func testPrefillMapsAndOmitsEmpty() throws {
        let profile = try completeProfile()
        let passport = try decode(Passport.self, """
        {"id":"22222222-2222-2222-2222-222222222222",
         "passport_number":"X1234567","expiry_date":"2030-01-01","citizenship_iso2":"GB"}
        """)
        let details = ApplicantDetailsPrefill.make(from: profile, passport: passport)

        XCTAssertEqual(details.string(.legalFirstName), "Ada")
        XCTAssertEqual(details.string(.passportNumber), "X1234567")
        XCTAssertEqual(details.string(.passportExpiry), "2030-01-01")
        XCTAssertEqual(details.string(.phone), "+44 20 7946 0000")
        // Empty/absent fields are not persisted as blank keys.
        XCTAssertNil(details.values[ApplicantDetails.Key.legalMiddleName.rawValue])
        XCTAssertNil(details.values[ApplicantDetails.Key.placeOfBirth.rawValue])
    }

    // MARK: - Completeness

    func testCompletenessPercentage() {
        let partial = ProfileCompleteness.compute(CompletenessInput(
            personalComplete: true, contactComplete: true, passports: 1,
            residencies: 0, education: 0, employment: 0, family: 0, travel: 0, background: 0))
        XCTAssertEqual(partial.completeCount, 3)
        XCTAssertEqual(partial.percent, 33) // round(3/9 * 100)

        let full = ProfileCompleteness.compute(CompletenessInput(
            personalComplete: true, contactComplete: true, passports: 2,
            residencies: 1, education: 1, employment: 1, family: 1, travel: 1, background: 1))
        XCTAssertEqual(full.percent, 100)
    }

    func testPersonalAndContactCompletePredicates() throws {
        XCTAssertTrue(ProfileCompleteness.personalComplete(try completeProfile()))
        XCTAssertTrue(ProfileCompleteness.contactComplete(try completeProfile()))
        let bare = try decode(Profile.self, #"{"id":"33333333-3333-3333-3333-333333333333"}"#)
        XCTAssertFalse(ProfileCompleteness.personalComplete(bare))
        XCTAssertFalse(ProfileCompleteness.contactComplete(bare))
    }

    // MARK: - Grouping

    @MainActor
    func testListSectionsOrderedByBucket() throws {
        let model = ApplicationsListModel()
        model.applications = [
            try application(status: "approved"),   // complete
            try application(status: "draft"),      // needs action
            try application(status: "paid"),       // in progress
        ]
        let titles = model.sections.map(\.title)
        XCTAssertEqual(titles, ["Needs action", "In progress", "Complete"])
    }

    // MARK: - Round-trip

    func testApplicationRoundTripPreservesUnknownDetailKeys() throws {
        let json = """
        {"id":"44444444-4444-4444-4444-444444444444",
         "user_id":"55555555-5555-5555-5555-555555555555",
         "product_id":"66666666-6666-6666-6666-666666666666",
         "passport_iso2":"gb","destination_iso2":"de","status":"draft",
         "applicant_details":{"legal_first_name":"Ada","details_confirmed":true,
           "history":[{"to":"draft","at":"2026-01-01T00:00:00Z"}]}}
        """
        let app = try decode(VisaApplication.self, json)
        XCTAssertEqual(app.passportIso2, "GB")          // normalized to uppercase
        XCTAssertEqual(app.destinationIso2, "DE")
        XCTAssertEqual(app.details.string(.legalFirstName), "Ada")
        XCTAssertTrue(app.details.detailsConfirmed)
        XCTAssertNotNil(app.applicantDetails["history"]) // server key survives

        let reencoded = try JSONEncoder().encode(app)
        let again = try JSONDecoder().decode(VisaApplication.self, from: reencoded)
        XCTAssertNotNil(again.applicantDetails["history"])
        XCTAssertTrue(again.details.detailsConfirmed)
    }

    private func application(status: String) throws -> VisaApplication {
        try decode(VisaApplication.self, """
        {"id":"\(UUID().uuidString)","user_id":"\(UUID().uuidString)",
         "product_id":"\(UUID().uuidString)","passport_iso2":"GB",
         "destination_iso2":"DE","status":"\(status)","applicant_details":{}}
        """)
    }
}

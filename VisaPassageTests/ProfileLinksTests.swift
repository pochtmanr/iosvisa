import XCTest
@testable import VisaPassage

/// IOS-06 logic: universal-link and Spotlight parsing, the passport sync diff,
/// and the once-per-version review prompt.
@MainActor
final class ProfileLinksTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "ProfileLinksTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func route(_ string: String) -> DeepLinkRouter.Route {
        DeepLinkRouter.parse(URL(string: string)!)
    }

    // MARK: DeepLinkRouter

    func testCorridorLinksWithAndWithoutLocale() {
        XCTAssertEqual(route("https://visapassage.com/travel/ukraine/spain"),
                       .corridor(from: "ukraine", to: "spain"))
        XCTAssertEqual(route("https://visapassage.com/ru/travel/ukraine/spain"),
                       .corridor(from: "ukraine", to: "spain"))
        XCTAssertEqual(route("https://www.visapassage.com/en/travel/Ukraine/Spain/"),
                       .corridor(from: "ukraine", to: "spain"))
    }

    func testPassportDestinationAndTrackerLinks() {
        XCTAssertEqual(route("https://visapassage.com/passports/germany"), .passport("germany"))
        XCTAssertEqual(route("https://visapassage.com/ru/destinations/japan"), .destination("japan"))
        XCTAssertEqual(route("https://visapassage.com/app/trackers"), .tracker(id: nil))
        XCTAssertEqual(route("https://visapassage.com/app/trackers/abc-123"), .tracker(id: "abc-123"))
        XCTAssertEqual(route("https://visapassage.com/app/trackers/abc-123/complete"), .tracker(id: "abc-123"))
        XCTAssertEqual(route("https://visapassage.com/app/trackers/new"), .tracker(id: nil))
    }

    func testUnclaimedPathsAreUnknown() {
        let compare = URL(string: "https://visapassage.com/passports/compare")!
        XCTAssertEqual(DeepLinkRouter.parse(compare), .unknown(compare))
        let blog = URL(string: "https://visapassage.com/blog/some-post")!
        XCTAssertEqual(DeepLinkRouter.parse(blog), .unknown(blog))
        let other = URL(string: "https://example.com/travel/a/b")!
        XCTAssertEqual(DeepLinkRouter.parse(other), .unknown(other))
    }

    func testExistingRoutesStillParse() {
        XCTAssertEqual(route("visapassage://visa-checker?passports=us,CA&to=de"),
                       .visaChecker(passports: ["US", "CA"], destination: "DE"))
        let callback = URL(string: "visapassage://auth/callback?code=xyz")!
        XCTAssertEqual(DeepLinkRouter.parse(callback), .authCallback(callback))
    }

    func testSpotlightIdentifiers() {
        XCTAssertEqual(DeepLinkRouter.parse(spotlightIdentifier: SpotlightIndexer.corridorID(from: "us", to: "es")),
                       .corridor(from: "US", to: "ES"))
        XCTAssertEqual(DeepLinkRouter.parse(spotlightIdentifier: SpotlightIndexer.passportID("ua")), .passport("UA"))
        XCTAssertNil(DeepLinkRouter.parse(spotlightIdentifier: "nonsense"))
    }

    // MARK: PassportSync

    private func row(_ iso: String, primary: Bool = false, number: String? = nil) -> PassportSync.Row {
        PassportSync.Row(id: UUID(), citizenshipISO2: iso, isPrimary: primary, passportNumber: number, expiryDate: nil)
    }

    func testSelectionPutsPrimaryFirstAndClamps() {
        let rows = [row("DE"), row("UA", primary: true), row("PL"), row("FR"), row("IT")]
        XCTAssertEqual(PassportSync.selection(from: rows), ["UA", "DE", "PL", "FR"])
    }

    func testPlanInsertsMissingAndFixesPrimary() {
        let de = row("DE", primary: true)
        let plan = PassportSync.plan(local: ["UA", "DE"], remote: [de])
        XCTAssertEqual(plan.insert.map(\.iso2), ["UA"])
        XCTAssertEqual(plan.insert.map(\.primary), [true])
        XCTAssertEqual(plan.setPrimary.map(\.id), [de.id])
        XCTAssertEqual(plan.setPrimary.map(\.primary), [false])
        XCTAssertTrue(plan.delete.isEmpty)
    }

    func testPlanNeverDeletesRowsWithDocumentDetails() {
        let bare = row("FR")
        let vault = row("GB", primary: true, number: "123456789")
        let plan = PassportSync.plan(local: ["UA"], remote: [bare, vault])
        XCTAssertEqual(plan.delete, [bare.id])
        XCTAssertEqual(plan.setPrimary.map(\.id), [vault.id], "The kept row loses primary")
        XCTAssertEqual(plan.insert.map(\.iso2), ["UA"])
    }

    func testPlanIsEmptyWhenInStep() {
        let plan = PassportSync.plan(local: ["UA", "PL"], remote: [row("UA", primary: true), row("PL")])
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: ReviewPrompter

    func testReviewAfterThreeDistinctCorridorsOncePerVersion() {
        let defaults = freshDefaults()
        let prompter = ReviewPrompter(defaults: defaults, version: "1.0")
        XCTAssertFalse(prompter.corridorViewed(from: "UA", to: "ES"))
        XCTAssertFalse(prompter.corridorViewed(from: "UA", to: "ES"), "Repeat views don't count")
        XCTAssertFalse(prompter.corridorViewed(from: "UA", to: "FR"))
        XCTAssertTrue(prompter.corridorViewed(from: "UA", to: "DE"))
        XCTAssertFalse(prompter.corridorViewed(from: "UA", to: "IT"), "Once per version")
        XCTAssertFalse(prompter.trackerCompleted())

        let next = ReviewPrompter(defaults: defaults, version: "1.1")
        XCTAssertTrue(next.trackerCompleted(), "A new version may ask again")
    }
}

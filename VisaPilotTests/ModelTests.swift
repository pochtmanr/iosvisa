import XCTest
@testable import VisaPilot

/// Pure-logic tests that don't need a running app or backend — safe to run in
/// headless CI (the OAuth/RLS paths need a device, per the plan's verification).
final class ModelTests: XCTestCase {

    func testFlagEmojiFromISO2() {
        XCTAssertEqual(Country.flagEmoji(forISO2: "US"), "🇺🇸")
        XCTAssertEqual(Country.flagEmoji(forISO2: "gb"), "🇬🇧")
        XCTAssertEqual(Country.flagEmoji(forISO2: "DE"), "🇩🇪")
    }

    func testVisaStatusDecodesUnknownGracefully() throws {
        let json = Data("\"something_new\"".utf8)
        let status = try JSONDecoder().decode(VisaStatus.self, from: json)
        XCTAssertEqual(status, .unknown)
    }

    func testApplicationStatusMapsLegacyValues() throws {
        func decode(_ raw: String) throws -> ApplicationStatus {
            try JSONDecoder().decode(ApplicationStatus.self, from: Data("\"\(raw)\"".utf8))
        }
        XCTAssertEqual(try decode("lead"), .draft)
        XCTAssertEqual(try decode("submitted"), .submittedToAuthority)
        XCTAssertEqual(try decode("rejected"), .refused)
        XCTAssertEqual(try decode("in_review"), .decisionPending)
    }

    func testApplicationStatusBuckets() {
        XCTAssertEqual(ApplicationStatus.ready.bucket, .needsAction)
        XCTAssertEqual(ApplicationStatus.inProgress.bucket, .inProgress)
        XCTAssertEqual(ApplicationStatus.approved.bucket, .complete)
    }

    func testVisaStatusHueMapping() {
        XCTAssertEqual(VisaStatus.visaFree.hue, .green)
        XCTAssertEqual(VisaStatus.noAdmission.hue, .red)
        XCTAssertEqual(VisaStatus.evisa.hue, .blue)
    }
}

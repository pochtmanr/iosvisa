import XCTest
@testable import VisaPassage

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

    func testVisaStatusHueMapping() {
        XCTAssertEqual(VisaStatus.visaFree.hue, .green)
        XCTAssertEqual(VisaStatus.noAdmission.hue, .red)
        XCTAssertEqual(VisaStatus.evisa.hue, .blue)
    }
}

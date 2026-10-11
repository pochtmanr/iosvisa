import XCTest
@testable import VisaPassage

/// Pure-logic M1 tests: nonce hashing and date round-trips.
/// Headless-safe — the OAuth/RLS/network paths are verified on a device per the
/// plan.
final class AuthM1Tests: XCTestCase {

    // MARK: Nonce

    func testSHA256KnownVector() {
        // Cross-checked against `shasum -a 256`.
        XCTAssertEqual(
            Nonce.sha256("visapassage-nonce"),
            "eebf7a3567873f8302f924e15473a81b335f5cc2e03d675a65639ea73d19de07"
        )
    }

    func testSHA256IsHex64() {
        let hash = Nonce.sha256("anything")
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) })
    }

    func testRandomNonceLengthAndCharset() {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        for length in [1, 16, 32, 64] {
            let nonce = Nonce.random(length: length)
            XCTAssertEqual(nonce.count, length)
            XCTAssertTrue(nonce.allSatisfy { allowed.contains($0) })
        }
    }

    func testRandomNonceVaries() {
        XCTAssertNotEqual(Nonce.random(), Nonce.random())
    }

    // MARK: DateOnly

    func testDateOnlyRoundTrip() {
        let date = DateOnly.parse("1992-03-14")
        XCTAssertNotNil(date)
        XCTAssertEqual(DateOnly.string(date), "1992-03-14")
    }

    func testDateOnlyToleratesTimestamp() {
        XCTAssertEqual(DateOnly.string(DateOnly.parse("2020-01-01T13:00:00Z")), "2020-01-01")
    }

    func testDateOnlyDisplay() {
        XCTAssertEqual(DateOnly.displayString("1992-03-14"), "14 Mar 1992")
    }

    func testDateOnlyHandlesNilAndEmpty() {
        XCTAssertNil(DateOnly.parse(nil))
        XCTAssertNil(DateOnly.parse(""))
        XCTAssertNil(DateOnly.string(nil))
        XCTAssertNil(DateOnly.displayString(nil))
    }
}

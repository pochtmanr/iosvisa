import XCTest
@testable import VisaPilot

/// Pure-logic M1 tests: nonce hashing, the onboarding gate, and date round-trips.
/// Headless-safe — the OAuth/RLS/network paths are verified on a device per the
/// plan.
final class AuthM1Tests: XCTestCase {

    // MARK: Nonce

    func testSHA256KnownVector() {
        // Cross-checked against `shasum -a 256`.
        XCTAssertEqual(
            Nonce.sha256("visapilot-nonce"),
            "a9757437e7e64e4c7813affb0f5d6de58dd9bf47b65924809f03e31a9ca48a3f"
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

    // MARK: Onboarding gate

    func testOnboardingGate() {
        let stamped = Date(timeIntervalSince1970: 1_700_000_000)
        // Finished the wizard → onboarded regardless of passports.
        XCTAssertTrue(OnboardingGate.isOnboarded(onboardingCompletedAt: stamped, passportCount: 0))
        // Never finished but holds a passport → onboarded (web parity backfill).
        XCTAssertTrue(OnboardingGate.isOnboarded(onboardingCompletedAt: nil, passportCount: 1))
        // Brand-new user → needs onboarding.
        XCTAssertFalse(OnboardingGate.isOnboarded(onboardingCompletedAt: nil, passportCount: 0))
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

    // MARK: Travel goals vocab

    func testTravelGoalRawValuesMatchWeb() {
        XCTAssertEqual(
            TravelGoal.allCases.map(\.rawValue),
            ["travel", "work_abroad", "immigrate", "study", "invest"]
        )
    }
}

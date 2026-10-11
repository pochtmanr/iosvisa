import XCTest

/// Minimal launch smoke test. Real flows (sign-in, checker, applications) get
/// UI tests as those milestones land.
final class SmokeUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}

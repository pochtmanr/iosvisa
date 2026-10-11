import XCTest

/// IOS-03: Explore's "See details" opens the corridor, which loads its verdict
/// and shows the sticky "Track this visa" button. Hits the live network.
final class CorridorUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-welcome.completed", "YES", "-passports.selected", "UA",
                                "-debug.tab", "explore"] + extra
        app.launch()
        return app
    }

    func testSeeDetailsOpensCorridor() {
        let app = launch(["-debug.exploreFocus", "DE"])
        let details = app.buttons["See details"]
        XCTAssertTrue(details.waitForExistence(timeout: 20))
        details.tap()

        let track = app.buttons.matching(identifier: "track").firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 30), "Corridor should load and offer tracking")
        XCTAssertTrue(app.staticTexts["Visa-free"].exists || app.staticTexts["VISA-FREE"].exists)
    }

    /// Screenshot tour for manual review. Runs only when `SCREENSHOT_DIR` is set
    /// (`TEST_RUNNER_SCREENSHOT_DIR=… xcodebuild test …`).
    func testScreenshotTour() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENSHOT_DIR"] else { throw XCTSkip("SCREENSHOT_DIR not set") }
        let pair = env["SCREENSHOT_PAIR"] ?? "UA-DE"
        let language = env["SCREENSHOT_LANG"] ?? "en"
        let app = XCUIApplication()
        let passport = String(pair.prefix(2))
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-welcome.completed", "YES",
                                "-passports.selected", passport, "-debug.tab", "explore", "-debug.corridor", pair]
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "track").firstMatch.waitForExistence(timeout: 30))
        sleep(2)
        let prefix = "\(pair)-\(language)"
        for index in 0..<7 {
            let data = XCUIScreen.main.screenshot().pngRepresentation
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(index).png"))
            app.swipeUp(velocity: .slow)
            sleep(1)
        }
    }
}

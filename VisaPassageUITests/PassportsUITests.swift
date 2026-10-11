import XCTest

/// IOS-04: Explore's toolbar opens the passport ranking, a row opens the
/// passport page, and the ranking scrolls without hitches. Hits the live network
/// on a cold cache.
final class PassportsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-welcome.completed", "YES", "-passports.selected", "UA",
                                "-debug.tab", "explore"] + extra
        app.launch()
        return app
    }

    func testRankingOpensPassportPage() {
        let app = launch()
        let ranking = app.buttons["explore.ranking"]
        XCTAssertTrue(ranking.waitForExistence(timeout: 10))
        ranking.tap()

        XCTAssertTrue(app.staticTexts["FULL RANKING"].waitForExistence(timeout: 30)
                      || app.staticTexts["Full ranking"].exists)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Germany")
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Germany'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.staticTexts["#9"].waitForExistence(timeout: 20), "Germany is #9 on the web")
    }

    /// Scroll hitches on the 237-row ranking. Run on an iPhone SE (3rd
    /// generation) simulator; the report's hitch ratio is the 60 fps check.
    func testRankingScrollPerformance() {
        let app = launch(["-debug.ranking", "YES"])
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["FULL RANKING"].waitForExistence(timeout: 30)
                      || app.staticTexts["Full ranking"].exists)

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            list.swipeUp(velocity: .fast)
            stopMeasuring()
            list.swipeDown(velocity: .fast)
        }
    }

    /// Design review aid: walks the ranking, a passport page and compare,
    /// scrolling each and attaching screenshots. Opt-in, so the normal suite
    /// stays fast: `TEST_RUNNER_CAPTURE_SCREENS=1 xcodebuild … test
    /// -only-testing:VisaPassageUITests/PassportsUITests/testCaptureScreens`,
    /// then export the attachments from the .xcresult.
    func testCaptureScreens() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_SCREENS"] == "1", "Set CAPTURE_SCREENS=1")
        let screens: [(String, [String])] = [
            ("ranking", ["-debug.ranking", "YES"]),
            ("passport-DE", ["-debug.passport", "DE"]),
            ("compare-DE-UA", ["-debug.compare", "DE,UA"]),
            ("compare-4", ["-debug.compare", "DE,IN,NG,US"]),
        ]
        for (name, args) in screens {
            let app = launch(args)
            sleep(6)
            for page in 0..<6 {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "\(name)-\(page)"
                shot.lifetime = .keepAlways
                add(shot)
                app.swipeUp(velocity: .slow)
                sleep(1)
            }
            app.terminate()
        }
    }
}

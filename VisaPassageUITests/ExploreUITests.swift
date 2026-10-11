import XCTest

/// Explore works for a guest: the passport picker lists the countries catalog
/// served by `CountryStore` through `CatalogCache`.
final class ExploreUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testGuestCanPickPassportFromCountryCatalog() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-welcome.completed", "YES",
                                "-passports.selected", ""]
        app.launch()

        let explore = app.tabBars.buttons["Explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 15))
        explore.tap()

        let choose = app.buttons["Choose passport"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()

        // Countries come from the catalog (cache or network).
        let germany = app.staticTexts["Germany"]
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Germ")
        XCTAssertTrue(germany.waitForExistence(timeout: 20), "Country catalog should list Germany")
    }

    /// First launch: welcome → Skip → purpose → pick a passport → Explore opens
    /// with the purpose, and Home shows the passport card.
    func testWelcomePickerLandsOnHomeWithPassport() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-welcome.completed", "NO",
                                "-passports.selected", ""]
        app.launch()

        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()

        // The landing's step 1: the purpose cards.
        let travel = app.buttons["purpose.travel"]
        XCTAssertTrue(travel.waitForExistence(timeout: 5), "Welcome asks for the purpose first")
        travel.tap()

        XCTAssertTrue(app.staticTexts["Pick your passport"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Ukra")
        let ukraine = app.buttons.containing(.staticText, identifier: "Ukraine").firstMatch
        XCTAssertTrue(ukraine.waitForExistence(timeout: 20))
        ukraine.tap()

        // Dismiss the keyboard's search, then continue.
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "Welcome finishes onto the tab shell")
        XCTAssertTrue(app.buttons["explore.purpose"].waitForExistence(timeout: 10), "A chosen purpose lands on Explore")

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["purpose.study"].waitForExistence(timeout: 10), "Home leads with the purpose cards")
        XCTAssertTrue(app.staticTexts["Ukraine"].waitForExistence(timeout: 10), "Home shows the picked passport")
        XCTAssertTrue(app.staticTexts["RANK"].exists || app.staticTexts["Rank"].exists)
    }
}

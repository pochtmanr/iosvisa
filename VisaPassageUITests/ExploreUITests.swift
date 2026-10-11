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
                                "-discovery.selectedPassports", ""]
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
}

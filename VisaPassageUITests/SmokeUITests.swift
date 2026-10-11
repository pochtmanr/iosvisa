import XCTest

/// Launch smoke tests: the app opens in guest mode straight onto the tab
/// shell, with no sign-in screen in the way.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchesAsGuestOnTabShell() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-welcome.completed", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "Tab bar should appear without signing in")
        for label in ["Home", "Explore", "My visas", "Settings"] {
            XCTAssertTrue(tabBar.buttons[label].exists, "Missing tab: \(label)")
        }

        tabBar.buttons["My visas"].tap()
        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 5), "Guests see the sign-in gate on My visas")
    }

    func testRussianTabLabels() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-welcome.completed", "YES"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        for label in ["Главная", "Поиск", "Мои визы", "Настройки"] {
            XCTAssertTrue(tabBar.buttons[label].exists, "Missing ru tab: \(label)")
        }
    }
}

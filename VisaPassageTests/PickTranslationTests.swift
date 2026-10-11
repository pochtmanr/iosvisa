import XCTest
@testable import VisaPassage

/// Mirrors the behaviour of `web/src/lib/i18n/pick-translation.ts`.
final class PickTranslationTests: XCTestCase {
    private let row: Translations = ["ru": ["name": "Испания", "summary": "Краткое описание"]]

    func testReturnsTranslationForLocale() {
        XCTAssertEqual(pickTranslation(row, field: "name", english: "Spain", locale: .ru), "Испания")
    }

    func testEnglishLocaleUsesTheColumn() {
        XCTAssertEqual(pickTranslation(row, field: "name", english: "Spain", locale: .en), "Spain")
    }

    func testMissingFieldFallsBackToEnglish() {
        XCTAssertEqual(pickTranslation(row, field: "capital", english: "Madrid", locale: .ru), "Madrid")
    }

    func testMissingOrEmptyTranslationsFallBackToEnglish() {
        XCTAssertEqual(pickTranslation(nil, field: "name", english: "Spain", locale: .ru), "Spain")
        XCTAssertEqual(pickTranslation([:], field: "name", english: "Spain", locale: .ru), "Spain")
    }

    func testNullColumnBecomesEmptyString() {
        XCTAssertEqual(pickTranslation(nil, field: "name", english: nil, locale: .ru), "")
    }

    func testOrNilPreservesNil() {
        XCTAssertNil(pickTranslationOrNil(nil, field: "summary", english: nil, locale: .ru))
        XCTAssertNil(pickTranslationOrNil(row, field: "summary", english: nil, locale: .en))
        XCTAssertEqual(pickTranslationOrNil(row, field: "summary", english: nil, locale: .ru), "Краткое описание")
    }

    func testKeyVariantPreservesFallback() {
        let nested: Translations = ["ru": ["work_rights_note": "Работать нельзя"]]
        XCTAssertEqual(pickTranslationKey(nested, key: "work_rights_note", locale: .ru, fallback: "No work"), "Работать нельзя")
        XCTAssertEqual(pickTranslationKey(nested, key: "work_rights_note", locale: .en, fallback: "No work"), "No work")
        XCTAssertNil(pickTranslationKey(nested, key: "other", locale: .ru, fallback: nil))
    }

    func testLocaleResolution() {
        XCTAssertEqual(AppLocale.resolve("ru"), .ru)
        XCTAssertEqual(AppLocale.resolve("ru-RU"), .ru)
        XCTAssertEqual(AppLocale.resolve("en-GB"), .en)
        XCTAssertEqual(AppLocale.resolve("de"), .en)
        XCTAssertEqual(AppLocale.resolve(nil), .en)
    }

    func testWebURLsFollowNextIntlRouting() {
        XCTAssertEqual(AppLocale.en.webURL(path: "/privacy").absoluteString, "https://visapassage.com/privacy")
        XCTAssertEqual(AppLocale.ru.webURL(path: "/privacy").absoluteString, "https://visapassage.com/ru/privacy")
        XCTAssertEqual(AppLocale.en.webURL(path: "").absoluteString, "https://visapassage.com/")
        XCTAssertEqual(AppLocale.ru.webURL(path: "").absoluteString, "https://visapassage.com/ru")
    }

    func testCountryDecodesTranslationsAndToleratesBadShape() throws {
        let good = try JSONDecoder().decode(Country.self, from: Data("""
        {"iso2":"ES","name":"Spain","translations":{"ru":{"name":"Испания"}}}
        """.utf8))
        XCTAssertEqual(good.localizedName(in: .ru), "Испания")

        let bad = try JSONDecoder().decode(Country.self, from: Data("""
        {"iso2":"ES","name":"Spain","translations":{"ru":{"name":42}}}
        """.utf8))
        XCTAssertNil(bad.translations)
        XCTAssertEqual(bad.localizedName(in: .ru), "Spain")
    }
}

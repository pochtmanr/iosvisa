import Foundation

// Swift port of `web/src/lib/i18n/pick-translation.ts` (migration 0128).
// Tier-1 catalog rows carry a `translations` jsonb of shape
// `{ "ru": { "<column>": "…" } }`; these helpers resolve a prose field for the
// active locale with graceful English fallback, so a partially translated row
// is always coherent (never a raw key, never a blank where English exists).

/// The `translations` jsonb column shape: locale → column name → translated prose.
typealias Translations = [String: [String: String]]

/// The two locales the app ships, matching the web's `en` + `ru`.
enum AppLocale: String, CaseIterable, Sendable {
    case en, ru

    /// The locale the UI is running in: Russian when iOS resolved the app to
    /// `ru` (system or per-app language), English otherwise.
    static var current: AppLocale {
        resolve(Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first)
    }

    /// Map any language identifier (`ru`, `ru-RU`, `en-GB`, …) onto a supported locale.
    static func resolve(_ identifier: String?) -> AppLocale {
        guard let identifier else { return .en }
        let language = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        return AppLocale(rawValue: language?.lowercased() ?? "") ?? .en
    }

    /// Native name, as the web language switcher shows it.
    var displayName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        }
    }

    /// A visapassage.com URL in this locale. English is unprefixed, Russian
    /// lives under `/ru`, matching the web's next-intl routing.
    func webURL(path: String) -> URL {
        let prefix = self == .en ? "" : "/\(rawValue)"
        let full = prefix + path
        return URL(string: full.isEmpty ? "/" : full, relativeTo: AppConfig.webBaseURL)?.absoluteURL
            ?? AppConfig.webBaseURL
    }
}

/// Resolve a NOT-NULL prose column (e.g. `countries.name`) for `locale`, falling
/// back to the row's English value, then to "" so callers always get a string.
func pickTranslation(
    _ translations: Translations?,
    field: String,
    english: String?,
    locale: AppLocale = .current
) -> String {
    translations?[locale.rawValue]?[field] ?? english ?? ""
}

/// Same, but preserves `nil` for a nullable prose column (e.g.
/// `visa_products.summary`) so a conditionally rendered field stays absent
/// rather than becoming an empty string.
func pickTranslationOrNil(
    _ translations: Translations?,
    field: String,
    english: String?,
    locale: AppLocale = .current
) -> String? {
    translations?[locale.rawValue]?[field] ?? english
}

/// Resolve nested jsonb prose (e.g. `visa_products.attributes.work_rights.note`)
/// by a flat mirror key (`work_rights_note`). Returns the caller's `fallback`
/// (which may be nil) when no translation exists.
func pickTranslationKey(
    _ translations: Translations?,
    key: String,
    locale: AppLocale = .current,
    fallback: String?
) -> String? {
    translations?[locale.rawValue]?[key] ?? fallback
}

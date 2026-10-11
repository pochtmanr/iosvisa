import Foundation

/// A row in `public.countries` (public-read catalog).
struct Country: Codable, Identifiable, Hashable, Sendable {
    var iso2: String
    var name: String
    var region: String?
    var flagEmoji: String?
    var isPassport: Bool?
    /// 3-digit ISO numeric (may be stored unpadded); bridges to the world-map
    /// TopoJSON whose geometries are keyed by numeric id.
    var isoNumeric: String?
    var slug: String?
    var coverageTier: String?
    /// Hand-written translations (`{ "ru": { "name": "Испания" } }`, migration 0128).
    var translations: Translations?

    var id: String { iso2 }

    /// The country name in the app's language, falling back to English.
    var displayName: String { localizedName(in: .current) }

    func localizedName(in locale: AppLocale) -> String {
        pickTranslation(translations, field: "name", english: name, locale: locale)
    }

    enum CodingKeys: String, CodingKey {
        case iso2
        case name
        case region
        case flagEmoji = "flag_emoji"
        case isPassport = "is_passport"
        case isoNumeric = "iso_numeric"
        case slug
        case coverageTier = "coverage_tier"
        case translations
    }

    init(iso2: String, name: String, region: String? = nil, flagEmoji: String? = nil,
         isPassport: Bool? = nil, isoNumeric: String? = nil, slug: String? = nil,
         coverageTier: String? = nil, translations: Translations? = nil) {
        self.iso2 = iso2
        self.name = name
        self.region = region
        self.flagEmoji = flagEmoji
        self.isPassport = isPassport
        self.isoNumeric = isoNumeric
        self.slug = slug
        self.coverageTier = coverageTier
        self.translations = translations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iso2 = try c.decode(String.self, forKey: .iso2)
        name = try c.decode(String.self, forKey: .name)
        region = try c.decodeIfPresent(String.self, forKey: .region)
        flagEmoji = try c.decodeIfPresent(String.self, forKey: .flagEmoji)
        isPassport = try c.decodeIfPresent(Bool.self, forKey: .isPassport)
        isoNumeric = try c.decodeIfPresent(String.self, forKey: .isoNumeric)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        coverageTier = try c.decodeIfPresent(String.self, forKey: .coverageTier)
        // A malformed translations blob must never drop the whole catalog.
        translations = try? c.decodeIfPresent(Translations.self, forKey: .translations)
    }

    /// Zero-padded 3-digit numeric code used to look up map geometry
    /// (e.g. "4" → "004", "840" → "840"). Nil when the catalog has no numeric.
    var paddedNumeric: String? {
        guard let isoNumeric, !isoNumeric.isEmpty else { return nil }
        let trimmed = isoNumeric.trimmingCharacters(in: .whitespaces)
        guard trimmed.count <= 3 else { return trimmed }
        return String(repeating: "0", count: 3 - trimmed.count) + trimmed
    }

    /// Derive a flag emoji from the ISO2 code when the column is empty.
    var flag: String {
        if let flagEmoji, !flagEmoji.isEmpty { return flagEmoji }
        return Country.flagEmoji(forISO2: iso2)
    }

    static func flagEmoji(forISO2 code: String) -> String {
        let base: UInt32 = 0x1F1E6
        var result = ""
        for scalar in code.uppercased().unicodeScalars where ("A"..."Z").contains(Character(scalar)) {
            if let flagScalar = UnicodeScalar(base + scalar.value - 65) {
                result.unicodeScalars.append(flagScalar)
            }
        }
        return result.isEmpty ? "🏳️" : result
    }
}

import Foundation

/// A `document_guides` row: how to get one kind of document issued in one
/// country (`XX` = the generic guide for any passport). English-only for now:
/// the web never selects its `translations` (ROADMAP known gaps).
struct DocumentGuideRow: Codable, Sendable, Hashable {
    var kind: String
    var countryIso2: String
    var howToObtain: String
    var issuingAuthority: String?
    var obtainURL: String?
    var typicalCost: String?
    var typicalTime: String?
    var sourceURL: String?
    var lastVerifiedAt: String?
    var confidence: String?

    static let columns =
        "kind,country_iso2,how_to_obtain,issuing_authority,obtain_url,typical_cost,typical_time,source_url,last_verified_at,confidence"

    enum CodingKeys: String, CodingKey {
        case kind, confidence
        case countryIso2 = "country_iso2"
        case howToObtain = "how_to_obtain"
        case issuingAuthority = "issuing_authority"
        case obtainURL = "obtain_url"
        case typicalCost = "typical_cost"
        case typicalTime = "typical_time"
        case sourceURL = "source_url"
        case lastVerifiedAt = "last_verified_at"
    }
}

/// A `document_kinds` row: the localized name of a document kind.
struct DocumentKind: Codable, Sendable, Hashable {
    var kind: String
    var name: String
    var sortOrder: Int?
    var translations: Translations?

    static let columns = "kind,name,sort_order,translations"

    var localizedName: String { pickTranslation(translations, field: "name", english: name) }

    enum CodingKeys: String, CodingKey {
        case kind, name, translations
        case sortOrder = "sort_order"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
        translations = try? c.decodeIfPresent(Translations.self, forKey: .translations)
    }
}

/// What a checklist row shows under "How to get it": the web's
/// `DocumentGuideResult` (`web/src/lib/documents/guides.ts`).
struct DocumentGuide: Sendable, Hashable {
    struct Source: Sendable, Hashable {
        var url: String?
        var verifiedAt: String?
        var confidence: String?
    }

    var howToObtain: String
    var issuingAuthority: String?
    var obtainURL: String?
    var typicalCost: String?
    var typicalTime: String?
    /// Nil for a per-requirement override, which carries no source.
    var source: Source?

    /// The link the guide's button opens: `obtain_url`, else the source page.
    var link: URL? {
        [obtainURL, source?.url].lazy.compactMap { $0 }.compactMap(URL.webLink).first
    }

    /// Resolution order, as on the web: the requirement's own override columns,
    /// then the guide for the passport's country, then the generic `XX` guide.
    static func resolve(
        _ requirement: DocumentRequirement,
        passport: String?,
        guides: [DocumentGuideRow]
    ) -> DocumentGuide? {
        if let own = requirement.howToObtain?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty {
            return DocumentGuide(
                howToObtain: own,
                issuingAuthority: requirement.issuingAuthority,
                obtainURL: requirement.obtainURL,
                typicalCost: requirement.typicalCost,
                typicalTime: requirement.typicalTime,
                source: nil
            )
        }
        guard let kind = requirement.kind else { return nil }
        let country = passport?.uppercased()
        let row = guides.first { $0.kind == kind && $0.countryIso2.uppercased() == country }
            ?? guides.first { $0.kind == kind && $0.countryIso2.uppercased() == "XX" }
        guard let row else { return nil }
        return DocumentGuide(
            howToObtain: row.howToObtain,
            issuingAuthority: row.issuingAuthority,
            obtainURL: row.obtainURL,
            typicalCost: row.typicalCost,
            typicalTime: row.typicalTime,
            source: Source(url: row.sourceURL, verifiedAt: row.lastVerifiedAt, confidence: row.confidence)
        )
    }
}

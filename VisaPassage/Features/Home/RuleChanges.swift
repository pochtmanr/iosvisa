import Foundation
import Observation
import Supabase

/// A published row of `policy_changes`, the source of the web `/changes` page.
struct PolicyChange: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var destinationIso2: String
    /// Nil when the change applies to every passport.
    var passportIso2: String?
    var changeKind: ChangeKind
    var title: String
    var summary: String
    var sourceURL: String?
    var effectiveDate: String?
    var publishedAt: String
    var translations: Translations?

    enum CodingKeys: String, CodingKey {
        case id
        case destinationIso2 = "destination_iso2"
        case passportIso2 = "passport_iso2"
        case changeKind = "change_kind"
        case title, summary
        case sourceURL = "source_url"
        case effectiveDate = "effective_date"
        case publishedAt = "published_at"
        case translations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        destinationIso2 = try c.decode(String.self, forKey: .destinationIso2)
        passportIso2 = try c.decodeIfPresent(String.self, forKey: .passportIso2)
        changeKind = try c.decode(ChangeKind.self, forKey: .changeKind)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        effectiveDate = try c.decodeIfPresent(String.self, forKey: .effectiveDate)
        publishedAt = try c.decode(String.self, forKey: .publishedAt)
        // A malformed translations blob must never drop the feed.
        translations = try? c.decodeIfPresent(Translations.self, forKey: .translations)
    }

    func localizedTitle(in locale: AppLocale = .current) -> String {
        pickTranslation(translations, field: "title", english: title, locale: locale)
    }

    /// `published_at` as a date (timestamptz, with or without fractional seconds).
    var publishedDate: Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: publishedAt) { return date }
        return ISO8601DateFormatter().date(from: publishedAt)
    }
}

/// `change_kind`, with the badge tones of the web `CHANGE_KINDS` (nil = muted).
enum ChangeKind: String, Codable, Sendable {
    case policyNew = "policy_new"
    case policyRelaxed = "policy_relaxed"
    case policyTightened = "policy_tightened"
    case feeChange = "fee_change"
    case processingChange = "processing_change"
    case dataCorrection = "data_correction"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChangeKind(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .policyNew: return String(localized: "New policy")
        case .policyRelaxed: return String(localized: "Relaxed")
        case .policyTightened: return String(localized: "Tightened")
        case .feeChange: return String(localized: "Fee change")
        case .processingChange: return String(localized: "Processing")
        case .dataCorrection: return String(localized: "Data correction")
        case .unknown: return String(localized: "Rule change")
        }
    }

    var hue: StatusHue? {
        switch self {
        case .policyNew: return .blue
        case .policyRelaxed: return .green
        case .policyTightened: return .red
        case .feeChange: return .yellow
        case .processingChange: return .teal
        case .dataCorrection, .unknown: return nil
        }
    }
}

/// Latest published rule changes, through `CatalogCache`. The same filter as
/// `fetchChanges` in `web/src/lib/changes/load-changes.ts` (published only,
/// newest first), narrowed to changes for every passport or for yours.
struct ChangesRepository: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared
    var cache: CatalogCache = .shared

    func latest(
        passport: String?,
        limit: Int = 5,
        onRefresh: @escaping @Sendable ([PolicyChange]) async -> Void = { _ in }
    ) async throws -> [PolicyChange] {
        let client = client
        let iso = passport?.uppercased()
        return try await cache.load(
            [PolicyChange].self,
            key: "changes:v1:\(iso ?? "all"):\(limit)",
            fetch: {
                var query = client
                    .from("policy_changes")
                    .select("id,destination_iso2,passport_iso2,change_kind,title,summary,source_url,effective_date,published_at,translations")
                    .not("published_at", operator: .is, value: "null")
                if let iso {
                    query = query.or("passport_iso2.is.null,passport_iso2.eq.\(iso)")
                }
                return try await query
                    .order("published_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
            },
            onRefresh: onRefresh
        ).value
    }
}

/// Home's rule-changes block state.
@MainActor
@Observable
final class RuleChangesModel {
    private(set) var changes: [PolicyChange] = []
    private(set) var loading = true
    private(set) var failed = false

    private let repo: ChangesRepository

    init(repo: ChangesRepository = ChangesRepository()) {
        self.repo = repo
    }

    func load(passport: String?) async {
        loading = changes.isEmpty
        defer { loading = false }
        do {
            changes = try await repo.latest(passport: passport) { [weak self] fresh in
                await self?.set(fresh)
            }
            failed = false
        } catch {
            failed = changes.isEmpty
        }
    }

    private func set(_ fresh: [PolicyChange]) { changes = fresh }
}

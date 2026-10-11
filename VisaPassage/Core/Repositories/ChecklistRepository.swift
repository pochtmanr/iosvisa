import Foundation
import Supabase

/// The public document catalog behind checklist rows: "how to get it" guides
/// (`document_guides`) and document-kind names (`document_kinds`). One cached
/// read per passport country, never one per row.
struct ChecklistRepository: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared
    var cache: CatalogCache = .shared

    static func guidesKey(_ passport: String?) -> String {
        "document-guides:v1:\((passport ?? "XX").uppercased()):\(DocumentGuideRow.columns)"
    }

    static let kindsKey = "document-kinds:v1:\(DocumentKind.columns)"

    /// Guides issued in the passport's country, plus the generic `XX` ones.
    func guides(passport: String?) async throws -> [DocumentGuideRow] {
        let countries = Array(Set(["XX", (passport ?? "XX").uppercased()])).sorted()
        let client = client
        return try await cache.load(
            [DocumentGuideRow].self,
            key: Self.guidesKey(passport),
            fetch: {
                try await client
                    .from("document_guides")
                    .select(DocumentGuideRow.columns)
                    .in("country_iso2", values: countries)
                    .execute()
                    .value
            }
        ).value
    }

    func kinds() async throws -> [DocumentKind] {
        let client = client
        return try await cache.load(
            [DocumentKind].self,
            key: Self.kindsKey,
            fetch: {
                try await client
                    .from("document_kinds")
                    .select(DocumentKind.columns)
                    .order("sort_order", ascending: true)
                    .execute()
                    .value
            }
        ).value
    }
}

/// Guides and kind names for one passport, loaded once and shared by the
/// corridor, the visa product, the checklist and the guide screens.
@MainActor
@Observable
final class DocumentCatalog {
    private(set) var guides: [DocumentGuideRow] = []
    private(set) var kinds: [String: DocumentKind] = [:]
    private(set) var passport: String?
    private var loadedFor: String?

    private let repo: ChecklistRepository

    init(repo: ChecklistRepository = ChecklistRepository()) {
        self.repo = repo
    }

    func load(passport: String?) async {
        let key = (passport ?? "XX").uppercased()
        guard loadedFor != key else { return }
        self.passport = passport?.uppercased()
        async let guideRows = try? repo.guides(passport: passport)
        async let kindRows = try? repo.kinds()
        let (g, k) = await (guideRows, kindRows)
        if let g { guides = g }
        if let k { kinds = Dictionary(k.map { ($0.kind, $0) }, uniquingKeysWith: { a, _ in a }) }
        // Retry next time when the network failed and nothing was cached.
        if g != nil { loadedFor = key }
    }

    func guide(for requirement: DocumentRequirement) -> DocumentGuide? {
        DocumentGuide.resolve(requirement, passport: passport, guides: guides)
    }

    func kindName(_ kind: String?) -> String? {
        kind.flatMap { kinds[$0]?.localizedName }
    }
}

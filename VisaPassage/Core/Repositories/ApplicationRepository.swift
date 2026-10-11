import Foundation
import Supabase

/// Reads and writes the signed-in user's `visa_applications` (and the related
/// timeline + document-requirement catalog) via PostgREST. RLS scopes every
/// row to the user. Server-mediated transitions (offer/claim/submit) are never
/// invoked here — the app only performs the owner-allowed `draft`→`ready`
/// transition and observes the rest.
struct ApplicationRepository {
    var client: SupabaseClient = SupabaseClientProvider.shared

    // MARK: Applications

    /// The user's applications, most-recently-updated first.
    func list() async throws -> [VisaApplication] {
        try await client
            .from("visa_applications")
            .select()
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    /// A single application by id (RLS-scoped), or nil.
    func get(id: UUID) async throws -> VisaApplication? {
        let rows: [VisaApplication] = try await client
            .from("visa_applications")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Insert a `draft` application with prefilled applicant details and return
    /// the stored row.
    func create(
        productId: UUID,
        passport: String,
        destination: String,
        applicantDetails: ApplicantDetails
    ) async throws -> VisaApplication {
        let userID = try await client.auth.session.user.id
        struct NewApplication: Encodable {
            let user_id: UUID
            let product_id: UUID
            let passport_iso2: String
            let destination_iso2: String
            let status: String
            let applicant_details: [String: JSONValue]
        }
        let payload = NewApplication(
            user_id: userID,
            product_id: productId,
            passport_iso2: passport.uppercased(),
            destination_iso2: destination.uppercased(),
            status: ApplicationStatus.draft.rawValue,
            applicant_details: applicantDetails.values
        )
        return try await client
            .from("visa_applications")
            .insert(payload, returning: .representation)
            .single()
            .execute()
            .value
    }

    /// Patch the `applicant_details` jsonb and return the updated row.
    @discardableResult
    func update(id: UUID, applicantDetails: ApplicantDetails) async throws -> VisaApplication {
        struct DetailsPatch: Encodable { let applicant_details: [String: JSONValue] }
        return try await client
            .from("visa_applications")
            .update(DetailsPatch(applicant_details: applicantDetails.values), returning: .representation)
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    /// Set the status for an owner-allowed transition (e.g. draft→ready, or
    /// ready→draft to re-open). Server-mediated statuses are never set here.
    @discardableResult
    func setStatus(id: UUID, to status: ApplicationStatus) async throws -> VisaApplication {
        struct StatusPatch: Encodable { let status: String }
        return try await client
            .from("visa_applications")
            .update(StatusPatch(status: status.rawValue), returning: .representation)
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    // MARK: Timeline

    /// The status-event trail for an application, oldest first.
    func timeline(applicationId: UUID) async throws -> [ApplicationStatusEvent] {
        try await client
            .from("application_status_events")
            .select()
            .eq("application_id", value: applicationId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    // MARK: Catalog

    /// The document checklist for a product, in display order (read straight
    /// from the public `visa_document_requirements` catalog).
    func checklist(productId: UUID) async throws -> [DocumentRequirement] {
        try await client
            .from("visa_document_requirements")
            .select()
            .eq("product_id", value: productId)
            .order("sort_order", ascending: true)
            .execute()
            .value
    }

    /// Product display names for a set of ids (used to label list rows).
    func productNames(ids: [UUID]) async throws -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable { let id: UUID; let name: String }
        let rows: [Row] = try await client
            .from("visa_products")
            .select("id,name")
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value
        return Dictionary(rows.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    /// Resolve a single product against the application's passport+destination
    /// (folds any per-nationality eligibility override), reusing the discovery
    /// resolver. Returns nil if the product is no longer offered.
    func resolvedProduct(
        productId: UUID,
        passport: String,
        destination: String,
        visa: VisaRepository = VisaRepository()
    ) async throws -> ResolvedVisaProduct? {
        let options = try await visa.destinationOptions(passport: passport, destination: destination)
        return options.products.first { $0.product.id == productId }
    }
}

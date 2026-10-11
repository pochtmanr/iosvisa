import Foundation
import Observation
import Supabase

/// Visa Tracker reads and writes, ported from `web/src/lib/trackers/queries.ts`
/// and `mutations.ts`. Everything runs with the signed-in user's session; RLS
/// (owner-only, migration 0240) is the real guard, so a tracker that isn't the
/// caller's simply isn't found.
struct TrackerRepository: Sendable {
    var client: SupabaseClient = SupabaseClientProvider.shared

    enum Failure: Error, Equatable {
        case session, notFound, invalid, saveFailed

        /// `tracker.errors.*`.
        var message: String {
            switch self {
            case .session: return String(localized: "Your session has expired. Please sign in again.")
            case .notFound: return String(localized: "We couldn't find that. Refresh the page and try again.")
            case .invalid: return String(localized: "Some details look wrong. Check them and try again.")
            case .saveFailed: return String(localized: "Couldn't save your changes. Please try again.")
            }
        }
    }

    private static let itemColumns =
        "id, tracker_id, requirement_id, kind, label, description, required, is_custom, sort_order, status, due_date"

    private func userID() async throws -> UUID {
        do { return try await client.auth.session.user.id } catch { throw Failure.session }
    }

    // MARK: Reads

    /// `listTrackers()`: active first, then archived; newest activity first.
    func list() async throws -> [TrackerSummary] {
        try await client
            .from("trackers")
            .select("*, items:tracker_items(id, label, status, required, due_date, sort_order), product:visa_products(more_info_url)")
            .order("archived_at", ascending: true, nullsFirst: true)
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    struct Product: Decodable, Hashable, Sendable {
        let id: UUID
        let name: String
        let moreInfoURL: String?
        let processingTimeDays: Int?
        let maxStayDays: Int?
        enum CodingKeys: String, CodingKey {
            case id, name
            case moreInfoURL = "more_info_url"
            case processingTimeDays = "processing_time_days"
            case maxStayDays = "max_stay_days"
        }
    }

    struct Detail: Sendable, Hashable {
        var tracker: Tracker
        var items: [TrackerItem]
        var events: [TrackerEvent]
        var product: Product?
        /// Catalog requirements added since the tracker was created.
        var newRequirementCount: Int
    }

    /// `loadTracker(id)`: the tracker, its checklist, the last 50 events, the
    /// product, and how many catalog requirements it doesn't have yet.
    func detail(_ id: UUID) async throws -> Detail {
        let rows: [Tracker] = try await client
            .from("trackers").select("*").eq("id", value: id).limit(1)
            .execute().value
        guard let tracker = rows.first else { throw Failure.notFound }

        async let itemsTask: [TrackerItem] = client
            .from("tracker_items").select(Self.itemColumns)
            .eq("tracker_id", value: id)
            .order("sort_order", ascending: true)
            .order("created_at", ascending: true)
            .execute().value
        async let eventsTask: [TrackerEvent] = client
            .from("tracker_events").select("id, from_status, to_status, note, created_at")
            .eq("tracker_id", value: id)
            .order("created_at", ascending: false)
            .limit(50)
            .execute().value
        let (items, events) = try await (itemsTask, eventsTask)

        var product: Product?
        var newCount = 0
        if let productID = tracker.productID {
            async let productTask: [Product] = client
                .from("visa_products")
                .select("id, name, more_info_url, processing_time_days, max_stay_days")
                .eq("id", value: productID).limit(1)
                .execute().value
            async let reqsTask: [DocumentRequirement] = client
                .from("visa_document_requirements").select()
                .eq("product_id", value: productID)
                .execute().value
            let (products, requirements) = try await (productTask, reqsTask)
            product = products.first
            let tracked = Set(items.compactMap(\.requirementID))
            newCount = requirements.filter { !tracked.contains($0.id) }.count
        }
        return Detail(tracker: tracker, items: items, events: events, product: product, newRequirementCount: newCount)
    }

    /// The open tracker for this destination and product, if any (the web's
    /// `/app/trackers/new` reuses it instead of creating a duplicate).
    func existing(destination: String, productID: UUID?) async throws -> UUID? {
        struct Row: Decodable { let id: UUID }
        var query = client.from("trackers").select("id")
            .eq("destination_iso2", value: destination.uppercased())
            .is("archived_at", value: nil)
        if let productID {
            query = query.eq("product_id", value: productID)
        } else {
            query = query.is("product_id", value: nil)
        }
        let rows: [Row] = try await query.limit(1).execute().value
        return rows.first?.id
    }

    // MARK: Writes

    /// `createTracker`: a tracker for a route with its checklist snapshotted.
    /// With a product, the items are its document requirements; without one,
    /// the generic travel set. The product must be offered on this passport →
    /// destination route.
    func create(passport: String, destination: String, productID: UUID?, title: String?) async throws -> UUID {
        let user = try await userID()
        let passport = passport.uppercased()
        let destination = destination.uppercased()
        guard passport.count == 2, destination.count == 2 else { throw Failure.invalid }

        var productName: String?
        var requirements: [DocumentRequirement] = []
        if let productID {
            let options = try await VisaRepository(client: client)
                .destinationOptions(passport: passport, destination: destination)
            guard let product = options.products.first(where: { $0.id == productID }) else { throw Failure.invalid }
            productName = product.product.name
            requirements = try await client
                .from("visa_document_requirements").select()
                .eq("product_id", value: productID)
                .order("sort_order", ascending: true)
                .execute().value
        }

        struct NewTracker: Encodable {
            let user_id: UUID
            let product_id: UUID?
            let passport_iso2: String
            let destination_iso2: String
            let title: String
            let status = "planning"
        }
        struct IDRow: Decodable { let id: UUID }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String((trimmed?.isEmpty == false ? trimmed! : productName ?? "Trip to \(destination)").prefix(120))
        let created: IDRow
        do {
            created = try await client.from("trackers")
                .insert(NewTracker(user_id: user, product_id: productID, passport_iso2: passport,
                                   destination_iso2: destination, title: name),
                        returning: .representation)
                .select("id").single()
                .execute().value
        } catch {
            throw Failure.saveFailed
        }

        struct NewItem: Encodable {
            let tracker_id: UUID
            let user_id: UUID
            let requirement_id: UUID?
            let kind: String?
            let label: String
            let description: String?
            let required: Bool
            let sort_order: Int
        }
        let items: [NewItem] = requirements.isEmpty
            ? TrackerBaseItems.items.enumerated().map { index, item in
                NewItem(tracker_id: created.id, user_id: user, requirement_id: nil, kind: nil,
                        label: item.label, description: item.description, required: true,
                        sort_order: (index + 1) * 10)
            }
            : requirements.enumerated().map { index, r in
                NewItem(tracker_id: created.id, user_id: user, requirement_id: r.id, kind: r.kind,
                        label: String(r.label.prefix(200)), description: r.description.map { String($0.prefix(2000)) },
                        required: r.required, sort_order: (index + 1) * 10)
            }
        struct NewEvent: Encodable {
            let tracker_id: UUID
            let user_id: UUID
            let from_status: String?
            let to_status: String
        }
        do {
            try await client.from("tracker_items").insert(items).execute()
            try await client.from("tracker_events")
                .insert(NewEvent(tracker_id: created.id, user_id: user, from_status: nil, to_status: "planning"))
                .execute()
        } catch {
            // Don't leave a tracker with a half-written checklist behind.
            _ = try? await client.from("trackers").delete().eq("id", value: created.id).execute()
            throw Failure.saveFailed
        }
        return created.id
    }

    /// `setTrackerStatus`: move to a new status and record it on the timeline.
    func setStatus(_ id: UUID, from current: TrackerStatus, to status: TrackerStatus) async throws {
        let user = try await userID()
        guard current != status else { return }
        struct Patch: Encodable { let status: String }
        do {
            try await client.from("trackers").update(Patch(status: status.rawValue)).eq("id", value: id).execute()
        } catch { throw Failure.saveFailed }
        struct NewEvent: Encodable {
            let tracker_id: UUID
            let user_id: UUID
            let from_status: String
            let to_status: String
        }
        _ = try? await client.from("tracker_events")
            .insert(NewEvent(tracker_id: id, user_id: user, from_status: current.rawValue, to_status: status.rawValue))
            .execute()
    }

    /// `setArchived`.
    func setArchived(_ id: UUID, _ archived: Bool) async throws {
        _ = try await userID()
        struct Patch: Encodable { let archived_at: String? }
        do {
            try await client.from("trackers")
                .update(Patch(archived_at: archived ? DashboardState.isoString(Date()) : nil))
                .eq("id", value: id).execute()
        } catch { throw Failure.saveFailed }
    }

    /// `deleteTracker`: the tracker with its items and timeline.
    func delete(_ id: UUID) async throws {
        _ = try await userID()
        do { try await client.from("trackers").delete().eq("id", value: id).execute() } catch { throw Failure.saveFailed }
    }

    /// `updateItem`: one checklist item's status.
    func setItemStatus(_ itemID: UUID, _ status: TrackerItemStatus) async throws {
        _ = try await userID()
        struct Patch: Encodable { let status: String }
        do {
            try await client.from("tracker_items").update(Patch(status: status.rawValue)).eq("id", value: itemID).execute()
        } catch { throw Failure.saveFailed }
    }

    /// `addCustomItem`: an item of the user's own at the end of the checklist.
    func addCustomItem(trackerID: UUID, label: String) async throws {
        let user = try await userID()
        let label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !label.isEmpty else { throw Failure.invalid }
        struct Last: Decodable { let sort_order: Int }
        let last: [Last] = (try? await client.from("tracker_items").select("sort_order")
            .eq("tracker_id", value: trackerID)
            .order("sort_order", ascending: false).limit(1)
            .execute().value) ?? []
        struct NewItem: Encodable {
            let tracker_id: UUID
            let user_id: UUID
            let label: String
            let required = false
            let is_custom = true
            let sort_order: Int
        }
        do {
            try await client.from("tracker_items")
                .insert(NewItem(tracker_id: trackerID, user_id: user, label: label,
                                sort_order: (last.first?.sort_order ?? 0) + 10))
                .execute()
        } catch { throw Failure.saveFailed }
    }

    /// `deleteCustomItem`: catalog items can't be removed, only marked "not needed".
    func deleteCustomItem(_ itemID: UUID) async throws {
        _ = try await userID()
        do {
            try await client.from("tracker_items").delete()
                .eq("id", value: itemID).eq("is_custom", value: true).execute()
        } catch { throw Failure.saveFailed }
    }

    /// `addNewRequirements`: append catalog requirements added since creation.
    func addNewRequirements(trackerID: UUID, productID: UUID, existing: [TrackerItem]) async throws -> Int {
        let user = try await userID()
        let requirements: [DocumentRequirement] = try await client
            .from("visa_document_requirements").select()
            .eq("product_id", value: productID)
            .order("sort_order", ascending: true)
            .execute().value
        let tracked = Set(existing.compactMap(\.requirementID))
        let missing = requirements.filter { !tracked.contains($0.id) }
        guard !missing.isEmpty else { return 0 }
        let maxOrder = existing.map(\.sortOrder).max() ?? 0
        struct NewItem: Encodable {
            let tracker_id: UUID
            let user_id: UUID
            let requirement_id: UUID
            let kind: String?
            let label: String
            let description: String?
            let required: Bool
            let sort_order: Int
        }
        do {
            try await client.from("tracker_items").insert(missing.enumerated().map { index, r in
                NewItem(tracker_id: trackerID, user_id: user, requirement_id: r.id, kind: r.kind,
                        label: String(r.label.prefix(200)), description: r.description.map { String($0.prefix(2000)) },
                        required: r.required, sort_order: maxOrder + (index + 1) * 10)
            }).execute()
        } catch { throw Failure.saveFailed }
        return missing.count
    }
}

// MARK: - Store

/// The signed-in user's trackers, shared by Home (the dashboard states), My
/// visas and Explore ("In my visas"). Reload after every write.
@MainActor
@Observable
final class TrackerStore {
    private(set) var trackers: [TrackerSummary] = []
    private(set) var loaded = false
    private(set) var loading = false
    private(set) var failed = false

    let repo: TrackerRepository

    init(repo: TrackerRepository = TrackerRepository()) {
        self.repo = repo
    }

    var state: DashboardState { DashboardState.from(trackers) }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            trackers = try await repo.list()
            failed = false
            loaded = true
        } catch {
            failed = true
        }
    }

    func clear() {
        trackers = []
        loaded = false
    }

    /// The open tracker for a destination's product (`trackedVisas`), keyed
    /// as the web keys it.
    func tracked(destination: String, productID: UUID) -> TrackerSummary? {
        trackers.first {
            !$0.tracker.isArchived && $0.tracker.destinationIso2 == destination.uppercased()
                && $0.tracker.productID == productID
        }
    }
}

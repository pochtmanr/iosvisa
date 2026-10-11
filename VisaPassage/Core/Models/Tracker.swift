import Foundation

// Visa Tracker: a Swift port of `web/src/lib/trackers/types.ts` and
// `dashboard-state.ts`. Schema: `web/supabase/migrations/0240_trackers.sql`.
// Statuses are set by the traveller, never inferred. "approved" and "refused"
// record what the authority decided, not a prediction.
//
// Timestamps stay ISO strings, as on the web, so ordering and the
// `YYYY-MM-DD` deadline comparisons behave identically on both clients.

enum TrackerStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case planning, collecting, ready, submitted
    case decisionPending = "decision_pending"
    case approved, refused, withdrawn

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TrackerStatus(rawValue: raw) ?? .planning
    }

    /// `tracker.status.*`.
    var label: String {
        switch self {
        case .planning: return String(localized: "Planning")
        case .collecting: return String(localized: "Collecting documents")
        case .ready: return String(localized: "Ready to submit")
        case .submitted: return String(localized: "status.submitted", defaultValue: "Submitted")
        case .decisionPending: return String(localized: "Awaiting decision")
        case .approved: return String(localized: "Visa granted")
        case .refused: return String(localized: "Refused")
        case .withdrawn: return String(localized: "Withdrawn")
        }
    }

    /// `TRACKER_STATUS_TONE`: nil is the neutral tone.
    var hue: StatusHue? {
        switch self {
        case .planning, .withdrawn: return nil
        case .collecting, .submitted: return .blue
        case .ready: return .purple
        case .decisionPending: return .yellow
        case .approved: return .green
        case .refused: return .red
        }
    }

    /// `CLOSED_STATUSES`: after these the checklist is history, not work.
    var isClosed: Bool { [.approved, .refused, .withdrawn].contains(self) }

    /// `stageOf`.
    var stage: TrackerStage {
        switch self {
        case .submitted, .decisionPending: return .submitted
        case .approved, .refused, .withdrawn: return .decision
        default: return .preparing
        }
    }

    /// `DECISION_STATUSES`.
    static let decisions: [TrackerStatus] = [.approved, .refused, .withdrawn]
}

/// The three stages the traveller sees (`STAGES`).
enum TrackerStage: String, CaseIterable, Sendable, Hashable {
    case preparing, submitted, decision

    /// `tracker.stage.*`.
    var label: String {
        switch self {
        case .preparing: return String(localized: "Preparing")
        case .submitted: return String(localized: "stage.submitted", defaultValue: "Submitted")
        case .decision: return String(localized: "Decision")
        }
    }

    /// `STAGE_STATUS`: the status written when the traveller picks a stage
    /// (Decision asks for the outcome instead).
    var status: TrackerStatus? {
        switch self {
        case .preparing: return .collecting
        case .submitted: return .submitted
        case .decision: return nil
        }
    }
}

enum TrackerItemStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case todo
    case inProgress = "in_progress"
    case done
    case notApplicable = "not_applicable"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TrackerItemStatus(rawValue: raw) ?? .todo
    }
}

struct Tracker: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var productID: UUID?
    var passportIso2: String?
    var destinationIso2: String
    var title: String
    var travellerName: String?
    var status: TrackerStatus
    var appointmentAt: String?
    var submitBy: String?
    var plannedEntryDate: String?
    var notes: String?
    var archivedAt: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, status, notes
        case productID = "product_id"
        case passportIso2 = "passport_iso2"
        case destinationIso2 = "destination_iso2"
        case travellerName = "traveller_name"
        case appointmentAt = "appointment_at"
        case submitBy = "submit_by"
        case plannedEntryDate = "planned_entry_date"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isArchived: Bool { archivedAt != nil }
}

struct TrackerItem: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var requirementID: UUID?
    var kind: String?
    var label: String
    var description: String?
    var required: Bool
    var isCustom: Bool
    var sortOrder: Int
    var status: TrackerItemStatus
    var dueDate: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, label, description, required, status
        case requirementID = "requirement_id"
        case isCustom = "is_custom"
        case sortOrder = "sort_order"
        case dueDate = "due_date"
    }

    init(id: UUID = UUID(), requirementID: UUID? = nil, kind: String? = nil, label: String,
         description: String? = nil, required: Bool = true, isCustom: Bool = false,
         sortOrder: Int = 0, status: TrackerItemStatus = .todo, dueDate: String? = nil) {
        self.id = id
        self.requirementID = requirementID
        self.kind = kind
        self.label = label
        self.description = description
        self.required = required
        self.isCustom = isCustom
        self.sortOrder = sortOrder
        self.status = status
        self.dueDate = dueDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        requirementID = try c.decodeIfPresent(UUID.self, forKey: .requirementID)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? true
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        status = try c.decodeIfPresent(TrackerItemStatus.self, forKey: .status) ?? .todo
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
    }
}

struct TrackerEvent: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var fromStatus: TrackerStatus?
    var toStatus: TrackerStatus
    var note: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, note
        case fromStatus = "from_status"
        case toStatus = "to_status"
        case createdAt = "created_at"
    }
}

/// A tracker with its items and product link, as `listTrackers()` selects it.
struct TrackerSummary: Codable, Identifiable, Sendable, Hashable {
    var tracker: Tracker
    var items: [TrackerItem]
    var moreInfoURL: String?

    var id: UUID { tracker.id }

    enum CodingKeys: String, CodingKey { case items, product }
    struct ProductLink: Codable, Hashable { var more_info_url: String? }

    init(tracker: Tracker, items: [TrackerItem], moreInfoURL: String? = nil) {
        self.tracker = tracker
        self.items = items
        self.moreInfoURL = moreInfoURL
    }

    init(from decoder: Decoder) throws {
        tracker = try Tracker(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([TrackerItem].self, forKey: .items) ?? []
        moreInfoURL = try c.decodeIfPresent(ProductLink.self, forKey: .product)?.more_info_url
    }

    func encode(to encoder: Encoder) throws {
        try tracker.encode(to: encoder)
    }

    var progress: TrackerProgress { TrackerProgress(items) }
}

/// `trackerProgress`: "not applicable" items don't count.
struct TrackerProgress: Hashable, Sendable {
    let total: Int
    let done: Int
    /// Required items not yet done.
    let requiredOpen: Int
    /// 0–1. A tracker with nothing to do counts as complete.
    let ratio: Double

    init(_ items: [TrackerItem]) {
        let counted = items.filter { $0.status != .notApplicable }
        total = counted.count
        done = counted.filter { $0.status == .done }.count
        requiredOpen = counted.filter { $0.required && $0.status != .done }.count
        ratio = counted.isEmpty ? 1 : Double(done) / Double(counted.count)
    }

    var percent: Int { Int((ratio * 100).rounded()) }
}

/// `nextDeadline`: the next date to act on among those still ahead (today
/// counts), comparing `YYYY-MM-DD` strings.
struct TrackerDeadline: Hashable, Sendable {
    enum Kind: String, Sendable { case appointment, submitBy = "submit_by", item }
    let date: String
    let kind: Kind

    static func next(for tracker: Tracker, items: [TrackerItem], today: String) -> TrackerDeadline? {
        var candidates: [TrackerDeadline] = []
        if let at = tracker.appointmentAt { candidates.append(.init(date: String(at.prefix(10)), kind: .appointment)) }
        if let by = tracker.submitBy { candidates.append(.init(date: by, kind: .submitBy)) }
        for item in items {
            if let due = item.dueDate, item.status != .done, item.status != .notApplicable {
                candidates.append(.init(date: due, kind: .item))
            }
        }
        return candidates.filter { $0.date >= today }.min { $0.date < $1.date }
    }

    /// `tracker.home.active.deadline.*`.
    var label: String {
        let shown = DateOnly.parse(date).map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? date
        switch kind {
        case .appointment: return String(localized: "Appointment \(shown)")
        case .submitBy: return String(localized: "Submit by \(shown)")
        case .item: return String(localized: "Document due \(shown)")
        }
    }
}

/// Which of the three dashboards a traveller sees (`dashboardState`).
enum DashboardState: Equatable {
    case new(history: [TrackerSummary])
    case active(focus: TrackerSummary, others: [TrackerSummary], recentApproval: TrackerSummary?, history: [TrackerSummary])
    case done(latest: TrackerSummary, history: [TrackerSummary])

    /// How long an approval stays on the dashboard once another visa is open.
    static let recentApprovalDays = 14

    var history: [TrackerSummary] {
        switch self {
        case let .new(history), let .active(_, _, _, history), let .done(_, history): return history
        }
    }

    /// `tracker.home.lede.*`.
    var lede: String {
        switch self {
        case .new: return String(localized: "Pick what the trip is for. We open the map with your passport and the visas that fit.")
        case .active: return String(localized: "Your application comes first. Tick documents off and keep moving.")
        case .done: return String(localized: "A decision is in. Here's a summary and what to do next.")
        }
    }

    /// UTC `YYYY-MM-DD`, like `toISOString().slice(0, 10)`.
    static func today(_ now: Date = Date()) -> String {
        String(isoString(now).prefix(10))
    }

    static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// `rankOpen`: earliest upcoming deadline first, then latest activity.
    static func rankOpen(_ open: [TrackerSummary], today: String) -> [TrackerSummary] {
        let deadline = Dictionary(uniqueKeysWithValues: open.map {
            ($0.id, TrackerDeadline.next(for: $0.tracker, items: $0.items, today: today)?.date)
        })
        return open.sorted { a, b in
            let da = deadline[a.id] ?? nil
            let db = deadline[b.id] ?? nil
            if let da, let db, da != db { return da < db }
            if da != nil && db == nil { return true }
            if da == nil && db != nil { return false }
            return a.tracker.updatedAt > b.tracker.updatedAt
        }
    }

    static func from(_ trackers: [TrackerSummary], now: Date = Date()) -> DashboardState {
        let today = today(now)
        let open = trackers.filter { !$0.tracker.isArchived && !$0.tracker.status.isClosed }
        let history = trackers
            .filter { $0.tracker.isArchived || $0.tracker.status.isClosed }
            .sorted { $0.tracker.updatedAt > $1.tracker.updatedAt }

        if !open.isEmpty {
            let ranked = rankOpen(open, today: today)
            let cutoff = isoString(now.addingTimeInterval(-Double(recentApprovalDays) * 86_400))
            let recent = history.first {
                !$0.tracker.isArchived && $0.tracker.status == .approved && $0.tracker.updatedAt >= cutoff
            }
            return .active(focus: ranked[0], others: Array(ranked.dropFirst()), recentApproval: recent, history: history)
        }
        if let latest = history.first(where: { !$0.tracker.isArchived && $0.tracker.status.isClosed }) {
            return .done(latest: latest, history: history)
        }
        return .new(history: history)
    }

    /// `daysBetween`: whole days between two ISO timestamps, never negative.
    static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let a = parseTimestamp(from), let b = parseTimestamp(to) else { return 0 }
        return max(0, Int((b.timeIntervalSince(a) / 86_400).rounded()))
    }

    static func parseTimestamp(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Postgres `2026-10-11 20:34:22.1+00` style.
        let alt = DateFormatter()
        alt.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX"] {
            alt.dateFormat = format
            if let d = alt.date(from: s) { return d }
        }
        return nil
    }
}

/// `BASE_ITEMS` (`web/src/lib/visa/travel-checklist.ts`): the generic set for a
/// tracker without a catalog product. Stored in English, as the web stores them.
enum TrackerBaseItems {
    static let items: [(label: String, description: String)] = [
        ("Valid passport", "Valid for at least 6 months beyond your planned departure, with blank pages for entry stamps."),
        ("Return or onward ticket", "Proof you'll leave before your permitted stay ends — a booked flight, train, or bus."),
        ("Proof of accommodation", "Hotel booking, rental agreement, or an invitation letter from your host."),
        ("Proof of sufficient funds", "Recent bank statements or a card showing you can cover the trip."),
        ("Travel insurance", "Medical and travel cover for your stay — required by some countries, sensible everywhere."),
        ("Purpose of visit", "Anything that shows why you're travelling — an itinerary, a conference invite, or booking confirmations."),
    ]
}

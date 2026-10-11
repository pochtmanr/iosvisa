import Foundation

/// A row in the public `visa_document_requirements` catalog — one document a
/// given product expects, with optional "how to obtain" guidance. Keyed by
/// `product_id` and ordered by `sort_order`. Mirrors the web
/// `DocumentRequirement` shape (the M3 checklist reads this table directly
/// rather than the `/api/applications/{id}/checklist` route).
struct DocumentRequirement: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var productID: UUID
    var label: String
    var description: String?
    var required: Bool
    var sortOrder: Int
    var kind: String?
    var howToObtain: String?
    var issuingAuthority: String?
    var obtainURL: String?
    var typicalCost: String?
    var typicalTime: String?

    enum CodingKeys: String, CodingKey {
        case id, label, description, required, kind
        case productID = "product_id"
        case sortOrder = "sort_order"
        case howToObtain = "how_to_obtain"
        case issuingAuthority = "issuing_authority"
        case obtainURL = "obtain_url"
        case typicalCost = "typical_cost"
        case typicalTime = "typical_time"
    }
}

/// One checklist line in the workspace Documents step: a requirement plus the
/// state of the user's attachment for it. In M3 every item is `.missing`
/// (uploading real files is M4); the type is shaped so M4 can populate
/// `.uploaded` / `.accepted` / `.rejected` without churning callers.
struct ChecklistItem: Identifiable, Hashable, Sendable {
    var requirement: DocumentRequirement
    var status: ChecklistItemStatus

    var id: UUID { requirement.id }
    var isSatisfied: Bool { status == .uploaded || status == .accepted }
}

enum ChecklistItemStatus: String, Sendable, Hashable {
    case missing, uploaded, accepted, rejected

    var label: String {
        switch self {
        case .missing: return String(localized: "Missing")
        case .uploaded: return String(localized: "Uploaded")
        case .accepted: return String(localized: "Accepted")
        case .rejected: return String(localized: "Needs replacement")
        }
    }

    var hue: StatusHue {
        switch self {
        case .missing: return .red
        case .uploaded: return .blue
        case .accepted: return .green
        case .rejected: return .yellow
        }
    }
}

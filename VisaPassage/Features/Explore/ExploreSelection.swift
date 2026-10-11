import Foundation
import Observation

/// Shared Explore navigation state, injected at the app root so Home and deep
/// links can steer Explore: Map or List, the status filter, the destination
/// whose panel is open, and a one-shot request to focus the search field.
/// The passports themselves live in `PassportPreference`.
@MainActor
@Observable
final class ExploreSelection {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case map, list
        var id: Self { self }
    }

    var mode: Mode = .map
    var filter: ExploreFilter = .all
    /// The checker's purpose (landing step 1, the Home cards). Travel paints
    /// entry status; the others paint routes. Changing it clears the filters,
    /// as the web checker does.
    var purpose: Purpose = .travel {
        didSet {
            guard purpose != oldValue else { return }
            filter = .all
            typeFilter = nil
        }
    }
    /// The visa-type chip on a route map (`typeFilter` on the web), or nil.
    var typeFilter: String?
    /// Optional age band on route maps: refines the working-holiday note only.
    var ageBand: AgeBand?
    /// The destination whose bottom panel is open on the map.
    var focusedDestination: String?
    /// A destination to push into detail, consumed once by `ExploreView`.
    var pendingDetail: String?
    /// A catalog screen to push (deep links: corridor, destination), consumed once by `ExploreView`.
    var pendingRoute: CatalogRoute?
    /// A passport page to push (`/passports/{slug}` deep links), consumed once by `ExploreView`.
    var pendingPassport: String?
    /// Set by Home's "Where to?" field; consumed once by the list.
    var focusSearch = false

    init() {
        #if DEBUG
        // Screenshots: `-debug.exploreMode list`, `-debug.exploreFocus TR`.
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "debug.exploreMode") == "list" { mode = .list }
        focusedDestination = defaults.string(forKey: "debug.exploreFocus")
        // `-debug.explorePurpose study`.
        if let raw = defaults.string(forKey: "debug.explorePurpose"), let p = Purpose(rawValue: raw) { purpose = p }
        #endif
    }

    /// Open Explore's list with the search field focused.
    func startSearch() {
        mode = .list
        focusSearch = true
    }

    /// Open the map with a purpose applied (a Home card, the welcome's purpose
    /// step): the web's `/app/explore?purpose=…`.
    func open(purpose: Purpose) {
        self.purpose = purpose
        mode = .map
        focusedDestination = nil
    }

    /// Open the map with one destination's panel showing.
    func show(destination iso2: String) {
        purpose = .travel
        filter = .all
        mode = .map
        focusedDestination = iso2.uppercased()
    }
}

/// The map key's status filter: visa-free / on arrival / eVisa / visa
/// required / no admission. eVisa also covers eTA, as the web map shades them alike.
enum ExploreFilter: String, CaseIterable, Identifiable, Sendable {
    case all, visaFree, onArrival, evisa, visaRequired, noAdmission

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .visaFree: return VisaStatus.visaFree.label
        case .onArrival: return VisaStatus.visaOnArrival.label
        case .evisa: return VisaStatus.evisa.label
        case .visaRequired: return VisaStatus.visaRequired.label
        case .noAdmission: return VisaStatus.noAdmission.label
        }
    }

    /// The status whose glyph keys this filter (nil for All).
    var swatch: VisaStatus? {
        switch self {
        case .all: return nil
        case .visaFree: return .visaFree
        case .onArrival: return .visaOnArrival
        case .evisa: return .evisa
        case .visaRequired: return .visaRequired
        case .noAdmission: return .noAdmission
        }
    }

    func matches(_ status: VisaStatus) -> Bool {
        switch self {
        case .all: return true
        case .visaFree: return status == .visaFree
        case .onArrival: return status == .visaOnArrival
        case .evisa: return status == .evisa || status == .eta
        case .visaRequired: return status == .visaRequired
        case .noAdmission: return status == .noAdmission
        }
    }
}

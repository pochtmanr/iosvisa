import Foundation

/// A row in the public `visa_requirements` bilateral matrix: the baseline visa
/// regime for a (passport → destination) pair. Drives the world-map shading and
/// the destination baseline chip.
struct VisaRequirement: Codable, Sendable, Hashable {
    var passportIso2: String
    var destinationIso2: String
    var status: VisaStatus
    var daysAllowed: Int?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case passportIso2 = "passport_iso2"
        case destinationIso2 = "destination_iso2"
        case status
        case daysAllowed = "days_allowed"
        case notes
    }
}

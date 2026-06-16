import Foundation

extension String {
    /// Trimmed value, or nil when empty — for writing optional DB columns
    /// without storing blank strings.
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Masked passport/ID display: "•••• 1234".
    var maskedTail: String {
        let tail = suffix(4)
        return tail.isEmpty ? "" : "•••• \(tail)"
    }
}

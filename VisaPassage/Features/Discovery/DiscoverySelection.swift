import Foundation
import Observation

/// Shared, app-wide discovery state: which passports the user is exploring with,
/// plus a one-shot destination requested by a deep link. Injected at the app
/// root so the selection survives tab switches; passports persist across launches
/// in `UserDefaults`.
@MainActor
@Observable
final class DiscoverySelection {
    /// Selected passport ISO2 codes (best-status is computed across all of them).
    var selectedPassports: [String] {
        didSet { persist() }
    }

    /// A destination ISO2 a deep link asked to open. Consumed once by the
    /// Discover view, then cleared.
    var pendingDestination: String?

    private let defaults: UserDefaults
    private static let passportsKey = "discovery.selectedPassports"
    private var didSeed = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.passportsKey) ?? ""
        selectedPassports = Self.parse(raw)
    }

    /// The passport whose routes drive the destination detail (first selected).
    var primaryPassport: String? { selectedPassports.first }

    /// Seed the default selection from a signed-in user's saved passports
    /// (primary first) the first time, if nothing is selected yet. Guests have
    /// no session, so the fetch fails quietly and the selection stays empty.
    func seedFromAccountIfEmpty(using repo: ProfileRepository = ProfileRepository()) async {
        guard !didSeed else { return }
        didSeed = true
        guard selectedPassports.isEmpty else { return }
        let passports = (try? await repo.passports()) ?? []
        let isos = passports
            .compactMap { $0.citizenshipISO2?.uppercased() }
            .filter { $0.count == 2 }
        if let primary = isos.first { selectedPassports = [primary] }
    }

    /// Toggle a passport in/out of the selection (keeps at least the tapped one).
    func toggle(_ iso2: String) {
        let code = iso2.uppercased()
        if let idx = selectedPassports.firstIndex(of: code) {
            selectedPassports.remove(at: idx)
        } else {
            selectedPassports.append(code)
        }
    }

    /// Hydrate from a deep link (`?passports=US,CA&to=DE`).
    func apply(passports: [String], destination: String?) {
        let cleaned = passports.map { $0.uppercased() }.filter { $0.count == 2 }
        if !cleaned.isEmpty { selectedPassports = cleaned }
        if let destination, destination.count == 2 {
            pendingDestination = destination.uppercased()
        }
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(selectedPassports.joined(separator: ","), forKey: Self.passportsKey)
    }

    private static func parse(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { $0.count == 2 }
    }
}

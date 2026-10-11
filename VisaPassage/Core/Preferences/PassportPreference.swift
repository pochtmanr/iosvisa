import Foundation
import Observation

/// The passports a guest travels on: up to four ISO2 codes, primary first.
/// Stored on the device under `passports.selected` (comma-joined, readable with
/// `@AppStorage`). Syncing to the `passports` table comes in IOS-06, and only
/// when signed in.
@MainActor
@Observable
final class PassportPreference {
    static let key = "passports.selected"
    /// IOS-01 stored an unbounded list here; migrated once on first read.
    static let legacyKey = "discovery.selectedPassports"
    static let maxCount = 4

    /// Selected passports, primary first. Never more than `maxCount`.
    private(set) var passports: [String]

    private let defaults: UserDefaults
    private var didSeed = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.key) {
            passports = Self.clean(Self.parse(raw))
        } else {
            passports = Self.clean(Self.parse(defaults.string(forKey: Self.legacyKey) ?? ""))
            defaults.set(passports.joined(separator: ","), forKey: Self.key)
            defaults.removeObject(forKey: Self.legacyKey)
        }
    }

    var primary: String? { passports.first }
    var isFull: Bool { passports.count >= Self.maxCount }

    func contains(_ iso2: String) -> Bool { passports.contains(iso2.uppercased()) }

    /// Replace the whole selection (deep links, the welcome picker). Clamped.
    func set(_ list: [String]) {
        passports = Self.clean(list)
        persist()
    }

    /// Add a passport at the end. Returns false when the list is full.
    @discardableResult
    func add(_ iso2: String) -> Bool {
        let code = iso2.uppercased()
        guard !contains(code), !isFull, Self.isISO2(code) else { return false }
        passports.append(code)
        persist()
        return true
    }

    func remove(_ iso2: String) {
        passports.removeAll { $0 == iso2.uppercased() }
        persist()
    }

    /// Remove when selected, add when there is room.
    func toggle(_ iso2: String) {
        if contains(iso2) { remove(iso2) } else { add(iso2) }
    }

    /// Move a selected passport to the front.
    func makePrimary(_ iso2: String) {
        let code = iso2.uppercased()
        guard let index = passports.firstIndex(of: code), index > 0 else { return }
        passports.remove(at: index)
        passports.insert(code, at: 0)
        persist()
    }

    /// Seed from a signed-in user's saved passports (primary first) the first
    /// time, if nothing is selected yet. Guests have no session, so the fetch
    /// fails quietly and the selection stays empty.
    func seedFromAccountIfEmpty(using repo: ProfileRepository = ProfileRepository()) async {
        guard !didSeed else { return }
        didSeed = true
        guard passports.isEmpty else { return }
        let saved = (try? await repo.passports()) ?? []
        let isos = saved.compactMap { $0.citizenshipISO2?.uppercased() }
        if !isos.isEmpty { set(isos) }
    }

    // MARK: - Helpers

    private func persist() {
        defaults.set(passports.joined(separator: ","), forKey: Self.key)
    }

    private static func parse(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Uppercase, valid ISO2 only, de-duplicated in order, at most `maxCount`.
    static func clean(_ list: [String]) -> [String] {
        var out: [String] = []
        for code in list.map({ $0.uppercased() }) where isISO2(code) && !out.contains(code) {
            out.append(code)
            if out.count == maxCount { break }
        }
        return out
    }

    private static func isISO2(_ code: String) -> Bool {
        code.count == 2 && code.allSatisfy { $0.isASCII && $0.isLetter }
    }
}

import CryptoKit
import Foundation

/// File-based JSON cache for public catalog data (countries, and later the
/// requirements slice, the ranking and corridors). One file per query key in
/// `Caches/catalog/`, so iOS may purge it under storage pressure.
///
/// Reads are stale-while-revalidate: a cached value is returned at once, even
/// past its TTL, and a stale one is refreshed in the background. Only a cold
/// miss waits on the network. That keeps the app instant and usable offline.
actor CatalogCache {
    static let shared = CatalogCache()

    /// The default freshness window for catalog data.
    static let defaultTTL: TimeInterval = 24 * 60 * 60

    /// A value read from disk, with its age relative to the TTL.
    struct Entry<Value: Sendable>: Sendable {
        let value: Value
        let storedAt: Date
        let isStale: Bool
    }

    /// The result of `load`: the value to show now, plus the background refresh
    /// (if one started) so callers and tests can await it.
    struct Load<Value: Sendable>: Sendable {
        let value: Value
        let source: Source
        let refresh: Task<Void, Never>?

        enum Source: Sendable, Equatable { case fresh, stale, network }
    }

    private struct Envelope<Payload: Codable>: Codable {
        let storedAt: Date
        let payload: Payload
    }

    private let directory: URL
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private var refreshing: Set<String> = []

    init(
        directory: URL? = nil,
        ttl: TimeInterval = CatalogCache.defaultTTL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("catalog", isDirectory: true)
        self.ttl = ttl
        self.now = now
    }

    // MARK: - Stale-while-revalidate

    /// Return the cached value for `key` immediately when there is one; refresh
    /// it in the background when it is stale and hand the fresh value to
    /// `onRefresh`. On a miss, fetch, store and return. A failed background
    /// refresh keeps the stale value; a failed cold fetch throws.
    func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        key: String,
        fetch: @escaping @Sendable () async throws -> Value,
        onRefresh: @escaping @Sendable (Value) async -> Void = { _ in }
    ) async throws -> Load<Value> {
        if let entry = read(type, key: key) {
            guard entry.isStale else {
                return Load(value: entry.value, source: .fresh, refresh: nil)
            }
            let refresh = startRefresh(key: key, fetch: fetch, onRefresh: onRefresh)
            return Load(value: entry.value, source: .stale, refresh: refresh)
        }
        let value = try await fetch()
        write(value, key: key)
        return Load(value: value, source: .network, refresh: nil)
    }

    private func startRefresh<Value: Codable & Sendable>(
        key: String,
        fetch: @escaping @Sendable () async throws -> Value,
        onRefresh: @escaping @Sendable (Value) async -> Void
    ) -> Task<Void, Never>? {
        // One refresh per key at a time.
        guard refreshing.insert(key).inserted else { return nil }
        return Task {
            defer { refreshing.remove(key) }
            guard let fresh = try? await fetch() else { return }
            write(fresh, key: key)
            await onRefresh(fresh)
        }
    }

    // MARK: - Raw access

    /// The cached value for `key`, or nil on a miss or an unreadable file
    /// (which is deleted so the next load refetches).
    func read<Value: Codable & Sendable>(_ type: Value.Type, key: String) -> Entry<Value>? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? Self.decoder.decode(Envelope<Value>.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let age = now().timeIntervalSince(envelope.storedAt)
        return Entry(value: envelope.payload, storedAt: envelope.storedAt, isStale: age >= ttl)
    }

    /// Store `value` under `key`. Failures are ignored: the cache is an
    /// optimisation, never a source of truth.
    func write<Value: Codable & Sendable>(_ value: Value, key: String) {
        guard let data = try? Self.encoder.encode(Envelope(storedAt: now(), payload: value)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    /// Keys are arbitrary query descriptions, so hash them into safe filenames.
    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

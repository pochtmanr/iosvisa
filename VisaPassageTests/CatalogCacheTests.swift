import XCTest
@testable import VisaPassage

/// `CatalogCache`: fresh hits skip the network, stale hits return at once and
/// refresh in the background, misses fetch and store, corrupt files are misses.
final class CatalogCacheTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A clock tests can move forward.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        func now() -> Date { lock.withLock { value } }
        func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
    }

    /// Counts fetches and returns a scripted value.
    private actor Source {
        private(set) var calls = 0
        var next: [String]
        init(_ next: [String]) { self.next = next }
        func fetch() throws -> [String] {
            calls += 1
            return next
        }
        func set(_ value: [String]) { next = value }
    }

    private struct Offline: Error {}

    private func makeCache(_ clock: Clock, ttl: TimeInterval = 60) -> CatalogCache {
        CatalogCache(directory: directory, ttl: ttl, now: { clock.now() })
    }

    func testMissFetchesAndStores() async throws {
        let clock = Clock()
        let cache = makeCache(clock)
        let source = Source(["DE"])

        let load = try await cache.load([String].self, key: "k", fetch: { try await source.fetch() })

        XCTAssertEqual(load.value, ["DE"])
        XCTAssertEqual(load.source, .network)
        let calls = await source.calls
        XCTAssertEqual(calls, 1)
        let stored = await cache.read([String].self, key: "k")
        XCTAssertEqual(stored?.value, ["DE"])
    }

    func testFreshHitDoesNotFetch() async throws {
        let clock = Clock()
        let cache = makeCache(clock)
        await cache.write(["FR"], key: "k")
        clock.advance(30)
        let source = Source(["XX"])

        let load = try await cache.load([String].self, key: "k", fetch: { try await source.fetch() })

        XCTAssertEqual(load.value, ["FR"])
        XCTAssertEqual(load.source, .fresh)
        XCTAssertNil(load.refresh)
        let calls = await source.calls
        XCTAssertEqual(calls, 0)
    }

    func testStaleHitReturnsOldValueThenRefreshes() async throws {
        let clock = Clock()
        let cache = makeCache(clock)
        await cache.write(["OLD"], key: "k")
        clock.advance(61)
        let source = Source(["NEW"])
        let refreshed = expectation(description: "onRefresh called with fresh data")

        let load = try await cache.load(
            [String].self, key: "k",
            fetch: { try await source.fetch() },
            onRefresh: { fresh in
                XCTAssertEqual(fresh, ["NEW"])
                refreshed.fulfill()
            }
        )

        XCTAssertEqual(load.value, ["OLD"], "Stale data is returned immediately")
        XCTAssertEqual(load.source, .stale)
        await load.refresh?.value
        await fulfillment(of: [refreshed], timeout: 2)
        let stored = await cache.read([String].self, key: "k")
        XCTAssertEqual(stored?.value, ["NEW"])
        XCTAssertEqual(stored?.isStale, false)
    }

    func testFailedBackgroundRefreshKeepsStaleValue() async throws {
        let clock = Clock()
        let cache = makeCache(clock)
        await cache.write(["OLD"], key: "k")
        clock.advance(61)

        let load = try await cache.load([String].self, key: "k", fetch: { throw Offline() })
        await load.refresh?.value

        XCTAssertEqual(load.value, ["OLD"])
        let stored = await cache.read([String].self, key: "k")
        XCTAssertEqual(stored?.value, ["OLD"])
    }

    func testColdMissWhileOfflineThrows() async {
        let cache = makeCache(Clock())
        do {
            _ = try await cache.load([String].self, key: "k", fetch: { throw Offline() })
            XCTFail("Expected the fetch error")
        } catch {
            XCTAssertTrue(error is Offline)
        }
    }

    func testCorruptFileIsTreatedAsMiss() async throws {
        let clock = Clock()
        let cache = makeCache(clock)
        await cache.write(["OK"], key: "k")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        try Data("not json".utf8).write(to: files[0])

        let missing = await cache.read([String].self, key: "k")
        XCTAssertNil(missing)
        let source = Source(["REFETCHED"])
        let load = try await cache.load([String].self, key: "k", fetch: { try await source.fetch() })
        XCTAssertEqual(load.value, ["REFETCHED"])
        XCTAssertEqual(load.source, .network)
    }

    func testKeysAreIsolated() async {
        let cache = makeCache(Clock())
        await cache.write(["A"], key: "countries")
        await cache.write(["B"], key: "ranking")
        let a = await cache.read([String].self, key: "countries")
        let b = await cache.read([String].self, key: "ranking")
        XCTAssertEqual(a?.value, ["A"])
        XCTAssertEqual(b?.value, ["B"])
    }

    func testCountryRoundTripsWithTranslations() async throws {
        let cache = makeCache(Clock())
        let spain = Country(iso2: "ES", name: "Spain", translations: ["ru": ["name": "Испания"]])
        await cache.write([spain], key: "countries")
        let back = await cache.read([Country].self, key: "countries")
        XCTAssertEqual(back?.value.first?.localizedName(in: .ru), "Испания")
        XCTAssertEqual(back?.value.first?.localizedName(in: .en), "Spain")
    }
}

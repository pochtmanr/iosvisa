import Foundation
import Supabase

/// Thin wrapper for the few server-only Next.js API routes that iOS can't reach
/// directly through PostgREST: PDF package, per-application checklist, document
/// download, and order/checkout creation.
///
/// Each call attaches the current Supabase access token as a Bearer header.
/// (Requires the small backend change to accept `Authorization: Bearer` on
/// these routes — see the plan's "Required backend changes".)
struct APIClient {
    var baseURL: URL = AppConfig.webBaseURL
    var session: () async throws -> Session = { try await SupabaseClientProvider.shared.auth.session }

    enum APIError: Error, LocalizedError {
        case http(status: Int, body: String)
        case decoding(Error)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .http(let status, let body): return "Request failed (\(status)): \(body)"
            case .decoding(let err): return "Could not decode response: \(err.localizedDescription)"
            case .invalidResponse: return "Invalid server response."
            }
        }
    }

    // MARK: Requests

    /// GET a decoded JSON payload from an authenticated route.
    func getJSON<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        let data = try await getData(path, query: query)
        do {
            return try JSONDecoder.visaPilot.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// GET raw bytes (e.g. the PDF package) from an authenticated route.
    func getData(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        try await attachAuth(&request)
        return try await send(request)
    }

    /// POST a JSON body and decode the JSON response (e.g. create an order).
    func postJSON<Body: Encodable, T: Decodable>(_ path: String, body: Body, as type: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.visaPilot.encode(body)
        try await attachAuth(&request)
        let data = try await send(request)
        do {
            return try JSONDecoder.visaPilot.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: Internals

    private func attachAuth(_ request: inout URLRequest) async throws {
        let token = try await session().accessToken
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

extension JSONDecoder {
    /// Shared decoder. Postgres timestamps come back as ISO-8601 with fractional
    /// seconds; we try both with and without.
    static let visaPilot: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: string)
                ?? ISO8601DateFormatter.plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let visaPilot: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension ISO8601DateFormatter {
    // Configured once and only ever read (parsing), so unsafe-nonisolated is
    // the correct annotation under Swift 6 strict concurrency.
    nonisolated(unsafe) static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

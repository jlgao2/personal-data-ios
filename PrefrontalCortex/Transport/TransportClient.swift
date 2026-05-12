import Foundation

enum TransportError: Error, LocalizedError {
    case notConfigured
    case unreachable(String)
    case unauthorized
    case bundleMissing
    case serverError(Int, String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:        return "Transport not configured"
        case .unreachable(let s):   return "Laptop offline: \(s)"
        case .unauthorized:         return "Auth error — check token in Settings"
        case .bundleMissing:        return "Bundle missing on laptop — run refresh.sh"
        case .serverError(let c, let m): return "Server error \(c): \(m)"
        case .decodingFailed(let e): return "Bundle decode failed: \(e.localizedDescription)"
        }
    }
}

struct HealthResponse: Decodable { let ok: Bool; let bundle_mtime: String? }
struct SamplesUploadResponse: Decodable { let written: Int; let path: String }

struct SampleUpload: Encodable {
    let ts: String
    let type: String
    let value: Double
    let unit: String?
}

struct DeviationUpload: Encodable {
    let client_id: String
    let ts: String
    let surface: String
    let surface_id: String?
    let direction: String
    let cause: String?
    let prescribed: String
    let actual: String
    let actual_quant: Double?
    let lock_in: Bool
    let note: String?
}

/// Typed contract for `POST /v1/sessions`. Field names match what
/// `pipeline/parsers/ios_sessions.py` expects on the laptop, so the JSON
/// shape produced by `JSONEncoder` is the wire format — no manual dict
/// assembly. If you add a field here, mirror it in the parser.
struct SessionUpload: Encodable {
    let client_id: String
    let ts: String            // ISO8601
    let sport: String         // UPPER_SNAKE (e.g. "CYCLING")
    let duration_min: Int
    let rpe: Int?
    let note: String
}

final class TransportClient {
    static let shared = TransportClient()

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func health() async throws -> HealthResponse {
        let url = try await resolveURL(path: "v1/health")
        let token = await TransportSettings.shared.token
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await session.data(for: req)
        try Self.assertOK(resp)
        return try Self.decode(HealthResponse.self, from: data)
    }

    func fetchBundle() async throws -> Data {
        let req = try await makeAuthedRequest(path: "v1/bundle", method: "GET", body: nil)
        let (data, resp) = try await session.data(for: req)
        try Self.assertOK(resp)
        return data
    }

    func uploadSamples(_ rows: [[String: Any]]) async throws -> SamplesUploadResponse {
        let body = try JSONSerialization.data(withJSONObject: rows, options: [])
        let req = try await makeAuthedRequest(path: "v1/samples", method: "POST", body: body)
        let (data, resp) = try await session.data(for: req)
        try Self.assertOK(resp)
        return try Self.decode(SamplesUploadResponse.self, from: data)
    }

    /// POST self-logged session(s) to /v1/sessions. Same response shape as samples.
    func uploadSessions(_ rows: [SessionUpload]) async throws -> SamplesUploadResponse {
        let body = try JSONEncoder().encode(rows)
        let req = try await makeAuthedRequest(path: "v1/sessions", method: "POST", body: body)
        let (data, resp) = try await session.data(for: req)
        try Self.assertOK(resp)
        return try Self.decode(SamplesUploadResponse.self, from: data)
    }

    // ── Helpers ────────────────────────────────────────────────────────────
    private func resolveURL(path: String) async throws -> URL {
        guard let base = await TransportSettings.shared.serverURL else {
            throw TransportError.notConfigured
        }
        return base.appendingPathComponent(path)
    }

    private func makeAuthedRequest(path: String, method: String, body: Data?) async throws -> URLRequest {
        let url = try await resolveURL(path: path)
        guard let token = await TransportSettings.shared.token, !token.isEmpty else {
            throw TransportError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private static func assertOK(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw TransportError.unreachable("non-HTTP response")
        }
        switch http.statusCode {
        case 200...299: return
        case 401:       throw TransportError.unauthorized
        case 404:       throw TransportError.bundleMissing
        default:        throw TransportError.serverError(http.statusCode, "")
        }
    }

    private static func decode<T: Decodable>(_ t: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(t, from: data) }
        catch { throw TransportError.decodingFailed(error) }
    }
}

extension TransportClient {
    /// Map any error into our TransportError taxonomy. Pass-through if already
    /// a TransportError; recognize DecodingError (bad bundle); URLError-or-other
    /// → unreachable with the localized description.
    static func wrap(_ error: Error) -> TransportError {
        if let t = error as? TransportError { return t }
        if error is DecodingError { return .decodingFailed(error) }
        if let u = error as? URLError { return .unreachable(u.localizedDescription) }
        return .unreachable(error.localizedDescription)
    }
}

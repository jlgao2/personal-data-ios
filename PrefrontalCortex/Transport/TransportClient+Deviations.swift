import Foundation

extension TransportClient {
    /// POST one deviation row to /v1/deviations. The server merges into the
    /// dated drop file and dedupes by client_id. Returns the same response
    /// shape as uploadSamples / uploadSessions.
    func uploadDeviation(_ entry: DeviationEntry,
                         clientID: String) async throws -> SamplesUploadResponse {
        let isoTS = ISO8601DateFormatter().string(from: entry.ts)
        let dateF = DateFormatter()
        dateF.dateFormat = "yyyy-MM-dd"
        dateF.locale = Locale(identifier: "en_US_POSIX")
        dateF.timeZone = .current
        let dateString = dateF.string(from: entry.ts)

        var payload: [String: Any] = [
            "client_id":  clientID,
            "ts":         isoTS,
            "date":       dateString,
            "surface":    entry.surface.rawValue,
            "surface_id": entry.surfaceID ?? "",
            "direction":  entry.direction.rawValue,
            "prescribed": entry.prescribed,
            "actual":     entry.actual,
            "lock_in":    entry.lockIn,
        ]
        if let cause = entry.cause { payload["cause"] = cause.rawValue }
        if let q     = entry.actualQuant { payload["actual_quant"] = q }
        if let note  = entry.note, !note.isEmpty { payload["note"] = note }

        return try await uploadDeviationsRaw([payload])
    }

    /// Lower-level: takes already-shaped dicts. Mirrors `uploadSessions`.
    func uploadDeviationsRaw(_ rows: [[String: Any]]) async throws -> SamplesUploadResponse {
        let body = try JSONSerialization.data(withJSONObject: rows, options: [])
        let req  = try await makeAuthedRequest_(path: "v1/deviations", method: "POST", body: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try TransportClient.assertOK_(resp)
        return try TransportClient.decode_(SamplesUploadResponse.self, from: data)
    }
}

// MARK: - Private bridges
//
// `makeAuthedRequest`, `assertOK`, and `decode<T:>` are private on
// TransportClient. These thin re-exports give the extension access without
// changing the original type's visibility.
private extension TransportClient {
    func makeAuthedRequest_(path: String, method: String, body: Data?) async throws -> URLRequest {
        guard let base = await TransportSettings.shared.serverURL else {
            throw TransportError.notConfigured
        }
        guard let token = await TransportSettings.shared.token, !token.isEmpty else {
            throw TransportError.notConfigured
        }
        let url = base.appendingPathComponent(path)
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
}

private extension TransportClient {
    static func assertOK_(_ resp: URLResponse) throws {
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
    static func decode_<T: Decodable>(_ t: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(t, from: data) }
        catch { throw TransportError.decodingFailed(error) }
    }
}

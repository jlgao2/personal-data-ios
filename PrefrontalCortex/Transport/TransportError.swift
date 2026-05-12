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

extension TransportError {
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

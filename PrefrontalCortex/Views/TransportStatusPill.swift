import SwiftUI

struct TransportStatusPill: View {
    @ObservedObject var settings: TransportSettings = .shared
    let bundleExportedAt: String?
    let lastError: TransportError?
    @Binding var presentSettings: Bool

    var body: some View {
        if let label, let color {
            Button {
                presentSettings = true
            } label: {
                Text(label)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(color.opacity(0.4)))
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
        }
    }

    private var label: String? {
        if !settings.isConfigured { return "Setup → Settings" }
        if let lastError = lastError {
            switch lastError {
            case .unauthorized:           return "Auth error"
            case .bundleMissing:          return "Run refresh.sh"
            case .unreachable:            return "Laptop offline"
            case .notConfigured:          return "Setup → Settings"
            case .serverError(let c, _):  return "Server \(c)"
            case .decodingFailed:         return "Bad bundle"
            }
        }
        if let bundleExportedAt, let days = staleDays(since: bundleExportedAt), days >= 1 {
            return "Bundle \(days)d old"
        }
        return nil
    }

    private var color: Color? {
        if !settings.isConfigured { return .yellow }
        if let lastError = lastError {
            switch lastError {
            case .unauthorized:   return .orange
            case .bundleMissing:  return .yellow
            case .unreachable:    return .gray
            case .notConfigured:  return .yellow
            case .serverError:    return .orange
            case .decodingFailed: return .orange
            }
        }
        if let bundleExportedAt, let days = staleDays(since: bundleExportedAt), days >= 1 {
            return .yellow
        }
        return nil
    }

    private func staleDays(since iso: String) -> Int? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return nil
        }
        let hours = Date().timeIntervalSince(date) / 3600
        guard hours >= 24 else { return nil }
        return Int(hours / 24)
    }
}

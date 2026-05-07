import SwiftUI

struct TransportStatusPill: View {
    @ObservedObject var settings: TransportSettings = .shared
    let lastError: TransportError?
    @Binding var presentSettings: Bool

    var body: some View {
        if let label, let color {
            Button {
                presentSettings = true
            } label: {
                Text(label)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.2))
                    .foregroundStyle(color)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    private var label: String? {
        if !settings.isConfigured { return "Setup → Settings" }
        switch lastError {
        case .none:                   return nil
        case .unauthorized:           return "Auth error"
        case .bundleMissing:          return "Run refresh.sh"
        case .unreachable:            return "Laptop offline"
        case .notConfigured:          return "Setup → Settings"
        case .serverError(let c, _):  return "Server \(c)"
        case .decodingFailed:         return "Bad bundle"
        }
    }

    private var color: Color? {
        if !settings.isConfigured { return .yellow }
        switch lastError {
        case .none:           return nil
        case .unauthorized:   return .orange
        case .bundleMissing:  return .yellow
        case .unreachable:    return .gray
        case .notConfigured:  return .yellow
        case .serverError:    return .orange
        case .decodingFailed: return .orange
        }
    }
}

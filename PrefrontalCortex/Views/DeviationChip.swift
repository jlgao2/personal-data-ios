import SwiftUI

/// Inline marker that replaces the surface's normal chrome when a deviation
/// is logged for today. Compact: shows actual + cause in monospaced caption.
struct DeviationChip: View {
    let entry: DeviationEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.cyan)
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.cyan)
                .tracking(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.cyan.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.35)))
        .accessibilityLabel(Text("Deviation: \(label)"))
    }

    private var icon: String {
        switch entry.direction {
        case .didLess:        return "minus.circle"
        case .didMore:        return "plus.circle"
        case .didDifferent:   return "arrow.triangle.swap"
        case .didSkip:        return "moon.zzz"
        case .didOutsidePlan: return "arrow.up.right"
        }
    }

    private var label: String {
        var bits: [String] = []
        if !entry.actual.isEmpty {
            bits.append(entry.actual)
        } else {
            bits.append(entry.direction.rawValue.replacingOccurrences(of: "_", with: " "))
        }
        if let cause = entry.cause {
            bits.append("· \(cause.rawValue.replacingOccurrences(of: "_", with: " "))")
        }
        return bits.joined(separator: " ")
    }
}

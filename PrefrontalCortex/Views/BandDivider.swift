import SwiftUI

/// Section divider that labels which TimeBand the content below belongs
/// to. Renders a small tag pill on the left and a thin horizontal rule
/// trailing to the right edge. If the divider's band matches the current
/// active band, the pill + rule glow in the band's accent color — gives
/// the user a quick visual anchor for "where in the day are we right now."
///
/// Used inside the Now tab's scroll to chunk sections chronologically:
/// MORNING / MIDDAY / WORKOUT / EVENING / NIGHT / ALL DAY.
struct BandDivider: View {
    let band: TimeBand?
    let label: String?

    @State private var current: TimeBand = .current()

    init(_ band: TimeBand) {
        self.band = band
        self.label = nil
    }

    /// Free-text divider (e.g., "ALL DAY") that doesn't map to a TimeBand.
    /// Renders in muted secondary color regardless of current band.
    init(label: String) {
        self.band = nil
        self.label = label
    }

    private var isActive: Bool { band != nil && band == current }
    private var tint: Color {
        if let b = band { return isActive ? b.accent : .secondary }
        return .secondary
    }
    private var text: String { band?.tag ?? (label ?? "") }

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.caption2.monospaced().bold())
                .tracking(2)
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(tint.opacity(isActive ? 0.7 : 0.3), lineWidth: 1))
                .clipShape(Capsule())
            Rectangle()
                .fill(tint.opacity(isActive ? 0.35 : 0.12))
                .frame(height: 1)
            if isActive {
                Text("NOW")
                    .font(.caption2.monospaced().bold())
                    .tracking(1.5)
                    .foregroundStyle(tint)
            }
        }
        .padding(.top, 6)
        .onAppear { current = .current() }
        .onReceive(NotificationCenter.default.publisher(for: .dayDidRollOver)) { _ in
            current = .current()
        }
    }
}

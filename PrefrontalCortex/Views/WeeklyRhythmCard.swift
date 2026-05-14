import SwiftUI

/// At-a-glance display of the user's weekly rhythm on the Plan tab.
/// Seven day-cells in a horizontal row with the kind underneath each
/// day initial. Tap → opens WeeklyRhythmEditorSheet.
///
/// Async load on appear — falls back to `WeeklyRhythm.empty()` if the
/// iCloud read fails (container unavailable, first-time install).
/// Subscribes to `.weeklyRhythmDidChange` so the row refreshes after
/// the editor sheet saves.
struct WeeklyRhythmCard: View {
    @State private var rhythm: WeeklyRhythm = .empty()
    @State private var showEditor: Bool = false
    @State private var loading: Bool = true

    var body: some View {
        Button { showEditor = true } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .weeklyRhythmDidChange)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $showEditor) {
            WeeklyRhythmEditorSheet()
        }
    }

    /// Body extracted to its own computed property — keeps the type-
    /// checker from timing out on the nested HStack + ForEach + Button
    /// + modifier chain. Same trick as the flow-field configs.
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                dayRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var header: some View {
        HStack {
            Text("WEEKLY RHYTHM")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)
            Spacer()
            Image(systemName: "pencil")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var dayRow: some View {
        HStack(spacing: 6) {
            ForEach(WeeklyRhythm.dayKeys, id: \.self) { key in
                dayCell(key: key, config: rhythm.config(for: key))
            }
        }
    }

    @ViewBuilder
    private func dayCell(key: String, config: WeeklyRhythm.DayConfig) -> some View {
        VStack(spacing: 4) {
            Text(key.prefix(1).uppercased())
                .font(.caption2.monospaced().bold())
                .foregroundStyle(.white.opacity(0.7))
            Text(config.kind.prefix(4).uppercased())
                .font(.system(size: 9).monospaced())
                .tracking(0.5)
                .foregroundStyle(kindColor(config.kind))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(kindColor(config.kind).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    /// Render-only tinting. Doesn't reach into Python — string-based so
    /// the user can introduce custom kinds without code changes.
    private func kindColor(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "rest", "recovery":      return .purple
        case "gym", "light_gym":      return .cyan
        case "run", "light_run":      return .orange
        case "mobility":              return .yellow
        case "improv":                return .pink
        case "travel":                return .indigo
        default:                      return .secondary
        }
    }

    private func reload() async {
        rhythm = await WeeklyRhythmStore.load()
        loading = false
    }
}

import SwiftUI

struct TodayHeaderView: View {
    let bundle: IOSBundle
    @EnvironmentObject var store: AppStore
    @State private var showSettings = false

    var dayKey: String {
        let dow = Calendar.current.component(.weekday, from: Date()) // 1=Sun
        let dayNum = ((dow + 5) % 7) + 1   // Mon=1
        return "Day \(dayNum)"
    }

    var todaySession: String {
        bundle.profile?.daily_protocol?[dayKey]?.session ?? "—"
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dayKey.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Text(todaySession)
                    .font(.title2.italic())
                    .foregroundStyle(.white)
                Text("Last refreshed \(prettyDate(bundle.exported_at))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TransportStatusPill(
                lastError: store.lastTransportError,
                presentSettings: $showSettings
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showSettings) {
            TransportSettingsView()
        }
    }

    private func prettyDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return iso.prefix(16).description
        }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

import SwiftUI

struct TransportStatusPill: View {
    @EnvironmentObject var store: AppStore

    enum State {
        case synced(exportedAt: String)
        case stale(hoursOld: Int)
        case errored(message: String)
        case noiCloud
        case pendingEdit
    }

    private var derivedState: State {
        if !iCloudPaths.isAvailable { return .noiCloud }
        guard let m = store.manifest else { return .pendingEdit }
        if m.status == "error" { return .errored(message: m.error ?? "Unknown error") }
        let age = staleHours(since: m.exported_at) ?? 0
        if age >= 6 { return .stale(hoursOld: age) }
        return .synced(exportedAt: m.exported_at)
    }

    var body: some View {
        switch derivedState {
        case .synced(let at):
            chip(color: .green,   label: "SYNCED", subtitle: shortTime(at))
        case .stale(let h):
            chip(color: .orange,  label: "STALE",  subtitle: "\(h)h old")
        case .errored(let msg):
            chip(color: .red,     label: "ERROR",  subtitle: msg)
        case .noiCloud:
            chip(color: .gray,    label: "NO iCLOUD", subtitle: "tap to sign in")
        case .pendingEdit:
            chip(color: .cyan,    label: "SAVING…", subtitle: nil)
        }
    }

    private func chip(color: Color, label: String, subtitle: String?) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2.monospaced().bold()).tracking(1.5)
            if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(color.opacity(0.6)))
        .clipShape(Capsule())
        .foregroundStyle(color)
    }

    private func staleHours(since iso: String) -> Int? {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return nil }
        return Int(Date().timeIntervalSince(d) / 3600)
    }
    private func shortTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); guard let d = f.date(from: iso) else { return "" }
        let df = DateFormatter(); df.timeStyle = .short; return df.string(from: d)
    }
}

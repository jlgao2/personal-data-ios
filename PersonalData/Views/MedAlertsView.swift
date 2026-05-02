import SwiftUI

struct MedAlertsView: View {
    let alerts: [MedAlertEvent]
    let avoidClasses: [MedAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MED WATCH")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)

            if alerts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No flags")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.green)
                        .tracking(2)
                    Text("MyChart medications all clean. Heads-up classes to mention to any new prescriber:")
                        .font(.footnote.italic())
                        .foregroundStyle(.secondary)
                    ForEach(avoidClasses) { a in
                        Text("• \(a.class) — \(a.reason)")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
            } else {
                VStack(spacing: 1) {
                    ForEach(alerts) { a in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(a.medication)
                                    .font(.body.italic())
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("⚠")
                                    .foregroundStyle(.red)
                            }
                            if let cls = a.drug_class {
                                Text(cls.uppercased())
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.red)
                                    .tracking(1.5)
                            }
                            if let r = a.reason {
                                Text(r)
                                    .font(.footnote.italic())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(.red).frame(width: 2)
                        }
                    }
                }
                .background(Color.white.opacity(0.05))
            }
        }
    }
}

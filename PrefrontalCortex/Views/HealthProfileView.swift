import SwiftUI

struct HealthProfileView: View {
    let profile: HealthProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HEALTH PROFILE")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(2)

            // Active conditions
            if let conds = profile.active_conditions {
                let lower = conds.lower_extremity ?? []
                let upper = conds.upper_extremity ?? []
                if !lower.isEmpty || !upper.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIVE CONDITIONS")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.cyan)
                            .tracking(2)
                        if !lower.isEmpty {
                            ConditionGroup(title: "Lower extremity", items: lower)
                        }
                        if !upper.isEmpty {
                            ConditionGroup(title: "Upper extremity", items: upper)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.4))
                }
            }

            // Current medications
            if let meds = profile.current_medications, !meds.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CURRENT MEDS")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                        .tracking(2)
                    ForEach(meds, id: \.self) { m in
                        Text("• \(m)")
                            .font(.footnote.italic())
                            .foregroundStyle(.white)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
            }

            // This-week priorities
            if let plan = profile.action_plan_immediate, !plan.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("THIS-WEEK PRIORITIES")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                        .tracking(2)
                    ForEach(plan, id: \.self) { p in
                        Text("• \(p)")
                            .font(.footnote.italic())
                            .foregroundStyle(.white)
                            .padding(.vertical, 1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
            }
        }
    }
}

private struct ConditionGroup: View {
    let title: String
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .tracking(1.5)
            ForEach(items, id: \.self) { c in
                Text("• \(c)")
                    .font(.footnote.italic())
                    .foregroundStyle(.white)
            }
        }
    }
}

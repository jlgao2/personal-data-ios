import SwiftUI

/// Floating glass tab bar. Active tab inline-expands to show its label;
/// a soft cyan glow morphs between tabs via matchedGeometryEffect. The
/// outer shape is an irregular squircle (continuous corners) — no crisp
/// edges, no rigid pill — to match the celestial / aura aesthetic.
struct CustomTabBar: View {
    @Binding var selected: ContentView.Tab
    @Namespace private var ns

    private struct Spec: Identifiable {
        let id: ContentView.Tab
        let icon: String
        let label: String
    }

    private let tabs: [Spec] = [
        .init(id: .interventions, icon: "target",                label: "NOW"),
        .init(id: .plan,          icon: "scope",                 label: "PLAN"),
        .init(id: .social,        icon: "person.2",              label: "SOCIAL"),
        .init(id: .profile,       icon: "person.text.rectangle", label: "PROFILE"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                button(for: tab)
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        // Soft cyan halo behind the bar — the glow.
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.cyan.opacity(0.06))
                .blur(radius: 18)
                .scaleEffect(1.04)
        }
        .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 28)
        .padding(.bottom, 10)
        .sensoryFeedback(.selection, trigger: selected)
    }

    @ViewBuilder
    private func button(for tab: Spec) -> some View {
        let isActive = selected == tab.id

        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                selected = tab.id
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.body)
                    .symbolEffect(.bounce.up.byLayer, value: isActive)
                if isActive {
                    Text(tab.label)
                        .font(.caption2.monospaced().weight(.semibold))
                        .tracking(1.5)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.6, anchor: .leading)),
                            removal: .opacity
                        ))
                }
            }
            .foregroundStyle(isActive ? Color.cyan : Color.white.opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: isActive ? .infinity : nil)
            .background {
                if isActive {
                    ZStack {
                        // Inner soft fill
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.cyan.opacity(0.18))
                            .matchedGeometryEffect(id: "active-pill", in: ns)
                        // Outer halo glow
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color.cyan.opacity(0.14))
                            .blur(radius: 10)
                            .scaleEffect(1.1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LivePressStyle())
    }
}

/// Subtle press feedback — scale 0.96 + slight dim, spring back.
struct LivePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

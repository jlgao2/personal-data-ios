import SwiftUI

/// Floating glass tab bar with a sliding cyan pill that morphs between tabs
/// via matchedGeometryEffect. Active tab gets an inline label that animates
/// in; inactive tabs are icon-only. Replaces the system tab bar (hidden via
/// `.toolbar(.hidden, for: .tabBar)` on each tab).
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
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
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
                    Capsule()
                        .fill(Color.cyan.opacity(0.18))
                        .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.35), lineWidth: 0.5))
                        .matchedGeometryEffect(id: "active-pill", in: ns)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LivePressStyle())
    }
}

/// Subtle press feedback — scale 0.96 + slight dim, spring back.
/// Use for any interactive element that should "breathe" on tap.
struct LivePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

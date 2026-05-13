import SwiftUI

/// Reusable modifier that attaches Spinoza's adequate-cause question
/// to any obligation card. Long-press → a two-option menu:
/// "From your nature" / "From outside" (plus Unset to clear).
///
/// When tagged outside, the card *exits* the Now tab — no dim, no
/// "OUTSIDE" guilt-tag. Dim-with-badge was a half-measure that kept
/// the imposed obligation in your field of view with a frame around
/// it; this preserves the data (the tag persists) without continuing
/// to surface the obligation as if it were yours. Untag any time and
/// it returns.
///
/// Apply with `.authorshipMenu(.workout).authorshipHidden(.workout)`
/// on the same view so the menu (long-press) remains reachable from
/// the surface even though the surface is currently hidden — wait,
/// that doesn't work: a hidden view can't be long-pressed. So the
/// re-entry path for outside-tagged surfaces is via the Profile-tab
/// authorship inventory (a separate screen surfacing all current
/// tags with toggles). Left as a TODO; for now, outside-tagged
/// surfaces are sticky until the user re-tags via DailyLockChip's
/// dot long-press (the dot keeps rendering even when its surface
/// is hidden, so the user has a re-entry handle).
extension View {
    /// Long-press menu to set authorship.
    func authorshipMenu(_ surface: AuthorshipSurface) -> some View {
        modifier(AuthorshipMenuModifier(surface: surface))
    }

    /// Conditional render — view returns EmptyView when surface is
    /// tagged outside. The Now tab's layout adjusts because the
    /// `if Authorship.get(s) != .outside` check is at the call site,
    /// not via opacity.
    func authorshipHidden(_ surface: AuthorshipSurface) -> some View {
        modifier(AuthorshipHideModifier(surface: surface))
    }
}

private struct AuthorshipMenuModifier: ViewModifier {
    let surface: AuthorshipSurface
    @State private var current: Authorship = .unset

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Section("Whose obligation?") {
                    Button {
                        AuthorshipStore.set(surface, to: .selfAuthored)
                        current = .selfAuthored
                    } label: {
                        Label("From your nature", systemImage: current == .selfAuthored ? "checkmark" : "circle")
                    }
                    Button {
                        AuthorshipStore.set(surface, to: .outside)
                        current = .outside
                    } label: {
                        Label("From outside", systemImage: current == .outside ? "checkmark" : "circle")
                    }
                    if current != .unset {
                        Button(role: .destructive) {
                            AuthorshipStore.set(surface, to: .unset)
                            current = .unset
                        } label: {
                            Label("Clear tag", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .onAppear { current = AuthorshipStore.get(surface) }
            .onReceive(NotificationCenter.default.publisher(for: .authorshipDidChange)) { _ in
                current = AuthorshipStore.get(surface)
            }
    }
}

private struct AuthorshipHideModifier: ViewModifier {
    let surface: AuthorshipSurface
    @State private var current: Authorship = .unset

    func body(content: Content) -> some View {
        Group {
            if current == .outside {
                EmptyView()
            } else {
                content
            }
        }
        .onAppear { current = AuthorshipStore.get(surface) }
        .onReceive(NotificationCenter.default.publisher(for: .authorshipDidChange)) { _ in
            current = AuthorshipStore.get(surface)
        }
    }
}

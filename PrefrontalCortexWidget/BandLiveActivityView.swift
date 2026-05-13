import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity rendering for the always-on band indicator. Shows the
/// current TimeBand's headline + subtitle on the lock screen; collapses
/// to a compact icon + tag in the Dynamic Island.
///
/// Color is keyed off `ContentState.accent` (a stable string set by the
/// host) so this file stays independent of the host's TimeBand enum.
@available(iOS 16.2, *)
struct BandLiveActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BandLiveActivityAttributes.self) { context in
            BandLockScreenView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(BandColor.swiftUI(context.state.accent))
        } dynamicIsland: { context in
            let color = BandColor.swiftUI(context.state.accent)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.tag)
                        .font(.caption2.monospaced().bold())
                        .tracking(2)
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.symbol)
                        .font(.title3)
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.headline)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.subtitle)
                        .font(.footnote.italic())
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(color)
            } compactTrailing: {
                Text(context.state.tag)
                    .font(.caption2.monospaced().bold())
                    .tracking(1.5)
                    .foregroundStyle(color)
            } minimal: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(color)
            }
            .keylineTint(color)
        }
    }
}

@available(iOS 16.2, *)
private struct BandLockScreenView: View {
    let state: BandLiveActivityAttributes.ContentState

    var body: some View {
        let color = BandColor.swiftUI(state.accent)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(state.tag)
                    .font(.caption2.monospaced().bold())
                    .tracking(2)
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
                    .clipShape(Capsule())
                Spacer()
                Image(systemName: state.symbol)
                    .font(.title3)
                    .foregroundStyle(color.opacity(0.85))
            }
            Text(state.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(state.subtitle)
                .font(.footnote.italic())
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stable string → SwiftUI Color map. Must match the keys produced by
/// `TimeBand.accentName` on the host side.
private enum BandColor {
    static func swiftUI(_ name: String) -> Color {
        switch name {
        case "orange": return .orange
        case "yellow": return .yellow
        case "cyan":   return .cyan
        case "indigo": return .indigo
        case "purple": return .purple
        default:       return .secondary
        }
    }
}

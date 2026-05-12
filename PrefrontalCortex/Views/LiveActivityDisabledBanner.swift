import SwiftUI
import UIKit

/// Inline banner shown above the Start pill when the user has Live
/// Activities disabled in Settings. Tapping deep-links to Settings;
/// the X dismisses the banner permanently (per-install, App Group flag).
///
/// Always degrades gracefully: workouts still proceed, the rectangular
/// widget remains the fallback surface.
struct LiveActivityDisabledBanner: View {
    @State private var visible: Bool = {
        if #available(iOS 16.2, *) {
            return WorkoutLiveActivity.shouldShowDisabledBanner
        }
        return false
    }()

    var body: some View {
        if visible {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Activities are off")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Tap to enable in Settings · widget still works")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button {
                    if #available(iOS 16.2, *) {
                        WorkoutLiveActivity.dismissDisabledBanner()
                    }
                    visible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.orange.opacity(0.4))
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}

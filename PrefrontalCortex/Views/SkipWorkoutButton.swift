import SwiftUI
import UIKit

/// Low-contrast text link below the Start pill. Long-press 2.0 s to commit;
/// the link visually fills with cyan from left to right as you hold. Release
/// before completion cancels (with a soft spring-back). On completion, the
/// SkipReasonSheet appears.
///
/// SwiftUI's LongPressGesture doesn't expose progress, so we model the fill
/// manually: a DragGesture starts a Timer onChanged that increments progress
/// every 50ms, and onEnded cancels if not yet at 1.0.
struct SkipWorkoutButton: View {

    @State private var pressProgress: Double = 0
    @State private var pressTimer: Timer?
    @State private var showReasonSheet = false
    @State private var didCommit = false

    private let holdDuration: Double = 2.0

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                Capsule()
                    .fill(Color.cyan.opacity(0.18))
                    .frame(width: geo.size.width * pressProgress)
            }
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                Text("hold to skip today")
            }
            .font(.caption2.italic())
            .foregroundStyle(.white.opacity(0.4))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 26)
        .background(Color.white.opacity(0.03), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startHold() }
                .onEnded   { _ in cancelIfIncomplete() }
        )
        .sheet(isPresented: $showReasonSheet) {
            SkipReasonSheet { reason in
                DailyLock.setWorkoutDone(source: .skip, reason: reason)
                _ = StreakState.refresh()
                _ = Achievements.refresh()
            }
            .presentationDetents([.medium])
        }
    }

    private func startHold() {
        if pressTimer != nil { return }
        didCommit = false
        let tickInterval: Double = 0.05
        pressTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { _ in
            withAnimation(.linear(duration: tickInterval)) {
                pressProgress = min(1.0, pressProgress + tickInterval / holdDuration)
            }
            if pressProgress >= 1.0 {
                stopTimer()
                didCommit = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showReasonSheet = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.4)) { pressProgress = 0 }
                }
            }
        }
    }

    private func cancelIfIncomplete() {
        guard !didCommit else { return }
        stopTimer()
        withAnimation(.easeOut(duration: 0.25)) { pressProgress = 0 }
    }

    private func stopTimer() {
        pressTimer?.invalidate()
        pressTimer = nil
    }
}

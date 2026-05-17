import SwiftUI

/// The Now tab, radically focused: exactly ONE thing — the chronological
/// moment that is current or most overdue right now. Not a list, not a
/// dot strip, not band sections. As you resolve the shown moment the
/// next one surfaces. Future moments stay hidden until their time.
///
/// "What to think about in the present" made literal: the screen holds
/// a single anchored obligation and its one action. Everything that used
/// to pile onto this tab (DailyLockChip, the full TimelineView list,
/// BandDividers, the section cards) is gone from here — those components
/// still live on the Plan tab where browsing the whole day is the point.
struct NowFocusView: View {
    let bundle: IOSBundle
    var onStartWorkout: () -> Void

    @State private var tick: Int = 0
    @State private var sheet: MomentSheet?

    enum MomentSheet: Identifiable {
        case supplements, mindful, reachOut
        var id: Int { hashValue }
    }

    /// One anchored daily obligation. `anchor` is today's clock time the
    /// moment belongs to (drives chronological ordering + "is it now").
    private struct Moment: Identifiable {
        let id: String
        let anchor: Date
        let tag: String
        let title: String
        let detail: String
        let isDone: () -> Bool
        let action: Action
    }

    private enum Action {
        case toggle(() -> Void)          // direct done flip (setter exists)
        case startWorkout                // launch the session tracker
        case openSheet(MomentSheet)      // hand off to the surface that owns the state
        case passive                     // informational (calendar / reach-out)
    }

    var body: some View {
        let chosen = pick()
        VStack(alignment: .leading, spacing: 18) {
            if let m = chosen {
                momentCard(m)
            } else {
                allClear
            }
            progressFooter
        }
        .id(tick)
        .onReceive(NotificationCenter.default.publisher(for: .dayDidRollOver)) { _ in tick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .customSlotsDidChange)) { _ in tick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .authorshipDidChange)) { _ in tick += 1 }
        .sheet(item: $sheet, onDismiss: { tick += 1 }) { which in
            switch which {
            case .supplements:
                if let supps = bundle.profile?.supplement_stack { StackView(items: supps) }
            case .mindful:
                MindfulEatingTodayView()
            case .reachOut:
                if let s = bundle.social { SocialView(summary: s) }
            }
        }
    }

    // MARK: - The single card

    @ViewBuilder
    private func momentCard(_ m: Moment) -> some View {
        let band = TimeBand.current()
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(m.tag)
                    .font(.caption2.monospaced().bold())
                    .tracking(2)
                    .foregroundStyle(band.accent)
                Spacer()
                Text(clock(m.anchor))
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(m.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !m.detail.isEmpty {
                Text(m.detail)
                    .font(.footnote.italic())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            actionControl(m)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(band.accent.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func actionControl(_ m: Moment) -> some View {
        switch m.action {
        case .toggle(let flip):
            primaryButton("Mark done") { flip(); tick += 1 }
        case .startWorkout:
            primaryButton("Start →") { onStartWorkout() }
        case .openSheet(let which):
            primaryButton("Open") { sheet = which }
        case .passive:
            EmptyView()
        }
    }

    private func primaryButton(_ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(label)
                .font(.callout.monospaced().bold())
                .tracking(1.5)
                .foregroundStyle(.cyan)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var allClear: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TimeBand.current().tag)
                .font(.caption2.monospaced().bold())
                .tracking(2)
                .foregroundStyle(TimeBand.current().accent)
            Text("Nothing right now.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Everything due so far is done. Close the app.")
                .font(.footnote.italic())
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(Color.black.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Minimal, non-interactive day progress. Replaces the old tappable
    /// dot strip — progress is a read-out that falls out of the moments,
    /// not a separate input surface.
    private var progressFooter: some View {
        let all = moments()
        let done = all.filter { $0.isDone() }.count
        return HStack(spacing: 6) {
            ForEach(0..<max(all.count, 1), id: \.self) { i in
                Rectangle()
                    .fill(i < done ? Color.cyan.opacity(0.6) : Color.white.opacity(0.12))
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Text("\(done)/\(all.count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 10)
        }
        .padding(.top, 4)
    }

    // MARK: - Moment construction + selection

    private func at(_ h: Int, _ m: Int = 0) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    private func authored(_ s: AuthorshipSurface) -> Bool {
        AuthorshipStore.get(s) != .outside
    }

    private func moments() -> [Moment] {
        var out: [Moment] = []

        if authored(.suppsAM) {
            out.append(Moment(id: "supps_am", anchor: at(7), tag: "MORNING",
                title: "AM supplements",
                detail: "Take the morning stack.",
                isDone: { DailyLock.isAMSuppsDone() },
                action: .openSheet(.supplements)))
        }
        if authored(.skincareAM) {
            out.append(Moment(id: "skin_am", anchor: at(8), tag: "MORNING",
                title: "Skincare — AM",
                detail: "Morning routine.",
                isDone: { DailyLock.isSkincareAMDone() },
                action: .toggle { DailyLock.setSkincareAMDone(!DailyLock.isSkincareAMDone()) }))
        }
        if authored(.mindful) {
            out.append(Moment(id: "mindful", anchor: at(12, 30), tag: "MIDDAY",
                title: "Eat mindfully",
                detail: "One meal, no screen, attention on the food.",
                isDone: { DailyLock.isMindfulEatingDone() },
                action: .openSheet(.mindful)))
        }
        if authored(.workout) {
            out.append(Moment(id: "workout", anchor: at(18), tag: "WORKOUT",
                title: workoutTitle(),
                detail: bundle.adapted_session?.prescribed ?? "Today's prescribed session.",
                isDone: { DailyLock.isWorkoutDone() },
                action: .startWorkout))
        }
        if let first = bundle.social?.reach_out?.first, let name = first.name {
            out.append(Moment(id: "reach", anchor: at(20), tag: "EVENING",
                title: "Reach out: \(name)",
                detail: first.about_what ?? (first.days_since_last.map { "\($0)d since last" } ?? ""),
                isDone: { false },
                action: .openSheet(.reachOut)))
        }
        if authored(.suppsPM) {
            out.append(Moment(id: "supps_pm", anchor: at(21, 30), tag: "NIGHT",
                title: "PM supplements",
                detail: "Take the evening stack.",
                isDone: { DailyLock.isPMSuppsDone() },
                action: .openSheet(.supplements)))
        }
        if authored(.skincarePM) {
            out.append(Moment(id: "skin_pm", anchor: at(22), tag: "NIGHT",
                title: "Skincare — PM",
                detail: "Evening routine.",
                isDone: { DailyLock.isSkincarePMDone() },
                action: .toggle { DailyLock.setSkincarePMDone(!DailyLock.isSkincarePMDone()) }))
        }
        for (i, slot) in CustomSlotStore.load().enumerated() {
            out.append(Moment(id: "custom_\(slot.id)", anchor: at(21, 30 + i + 1),
                tag: "NIGHT", title: slot.fullName, detail: "Custom daily slot.",
                isDone: { CustomSlotStore.isDone(slotID: slot.id) },
                action: .toggle { CustomSlotStore.toggle(slotID: slot.id) }))
        }
        return out.sorted { $0.anchor < $1.anchor }
    }

    /// The single moment to surface: the latest pending moment whose
    /// anchor time has arrived (you're at/past it — current or overdue).
    /// If nothing is due yet, the earliest upcoming pending moment. If
    /// every pending moment is resolved, nil → "Nothing right now."
    private func pick() -> Moment? {
        let now = Date()
        let pending = moments().filter { !$0.isDone() }
        guard !pending.isEmpty else { return nil }
        let due = pending.filter { $0.anchor <= now.addingTimeInterval(15 * 60) }
        return due.last ?? pending.first
    }

    private func workoutTitle() -> String {
        if let day = bundle.adapted_session?.program_day { return "Train · \(day)" }
        return "Train"
    }

    private func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mma"
        f.amSymbol = "am"; f.pmSymbol = "pm"
        return f.string(from: d)
    }
}

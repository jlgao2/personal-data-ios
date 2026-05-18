import SwiftUI

/// The Now tab as a dynamic scrolling wheel.
///
/// Design intent (per feedback): not a sterile hero + flat list — the
/// delightful, band-coloured language back, the whole day as a vertical
/// wheel you spin through. The card nearest screen-centre is full-size
/// and bright (the focus); neighbours scale down, fade, blur and curve
/// away in 3D. `.viewAligned` snap gives the resistance — it settles
/// onto a card instead of free-scrolling.
///
/// Ordering is by TimeBand (morning → midday → workout → evening →
/// night), NOT fabricated clock times. A moment shows a clock time
/// ONLY when it is a real calendar event; everything else shows its
/// band label. The workout is always a card in the wheel and always
/// tappable to start — never buried behind a synthetic 6pm anchor.
struct NowFocusView: View {
    let bundle: IOSBundle
    var onStartWorkout: () -> Void
    var onRefresh: (() async -> Void)? = nil

    @State private var tick = 0
    @State private var scrollID: String?
    @State private var sheet: MomentSheet?
    /// Bumped when a moment is marked done — drives the success haptic.
    @State private var completedPulse = 0

    enum MomentSheet: Identifiable {
        case supplements, mindful, reachOut
        var id: Int { hashValue }
    }

    private struct Moment: Identifiable {
        let id: String
        let band: TimeBand
        let order: Int            // band index * 100 + within-band slot
        let title: String
        let detail: String
        let eventTime: Date?      // non-nil ONLY for real calendar events
        let isDone: () -> Bool
        let action: Action
        // When set, the card renders this supplement stack inline
        // (StackView's check-off period buttons) instead of a generic
        // title + "Open" — so the checkboxes are in the wheel itself.
        var inlineSupps: [Supplement]? = nil
        // True when its authorship surface is tagged "from outside".
        // Per Authorship.swift's design these stay VISIBLE (dim, and
        // not auto-focused) rather than disappearing from the wheel.
        var isOutside: Bool = false
    }

    private enum Action {
        case toggle(() -> Void)
        case startWorkout
        case openSheet(MomentSheet)
        case passive

        var isPassive: Bool { if case .passive = self { return true }; return false }
    }

    var body: some View {
        let all = moments()
        Group {
            if all.isEmpty {
                allClear
            } else {
                wheel(all)
            }
        }
        .frame(maxWidth: .infinity)
        .id(tick)
        .onAppear { if scrollID == nil { scrollID = pick(all)?.id } }
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

    // MARK: - The wheel

    @ViewBuilder
    private func wheel(_ all: [Moment]) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 14) {
                // Top/bottom spacers so the first and last card can
                // reach screen-centre (the wheel's focal line).
                Color.clear.frame(height: 120)
                ForEach(all) { m in
                    card(m)
                        .scrollTransition(.interactive, axis: .vertical) { view, phase in
                            // Continuous, not binary: distance from the
                            // centre line (0 at focus → ~1 at the edges)
                            // drives a smooth scale-down + fade + blur as
                            // a card scrolls away.
                            let d = min(abs(phase.value), 1)
                            return view
                                .opacity(1 - 0.78 * d)        // 1.0 → 0.22
                                .scaleEffect(1 - 0.24 * d)    // 1.0 → 0.76
                                .blur(radius: 3.5 * d)        // 0   → 3.5
                                .rotation3DEffect(
                                    .degrees(phase.value * -20),
                                    axis: (x: 1, y: 0, z: 0),
                                    perspective: 0.5
                                )
                        }
                        .id(m.id)
                }
                Color.clear.frame(height: 120)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollID, anchor: .center)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await onRefresh?() }
        // Delight: a crisp selection tick every time a new card snaps
        // to the focal line (the wheel's "resistance" you can feel),
        // and a success thunk when a moment is marked done.
        .sensoryFeedback(.selection, trigger: scrollID)
        .sensoryFeedback(.success, trigger: completedPulse)
        .animation(.spring(response: 0.42, dampingFraction: 0.74),
                   value: scrollID)
    }

    // MARK: - A card

    @ViewBuilder
    private func card(_ m: Moment) -> some View {
        let done = m.isDone()
        let accent = m.band.accent
        let focused = (m.id == scrollID)
        let corner: CGFloat = 18
        ZStack(alignment: .topTrailing) {
            // Soft per-band SF Symbol watermark — instant identity +
            // richness behind the content; brightens when focused.
            Image(systemName: m.band.symbol)
                .font(.system(size: 92, weight: .semibold))
                .foregroundStyle(accent.opacity(done ? 0.05 : (focused ? 0.18 : 0.11)))
                .rotationEffect(.degrees(-8))
                .offset(x: 24, y: -16)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(m.band.tag)
                        .font(.caption2.monospaced().bold())
                        .tracking(2)
                        .foregroundStyle(accent)
                    if m.isOutside {
                        Text("· FROM OUTSIDE")
                            .font(.caption2.monospaced())
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer()
                    // Clock ONLY for real calendar events.
                    if let t = m.eventTime {
                        Text(clock(t))
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.6))
                    } else if done {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: done)
                    }
                }
                Text(m.title)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .strikethrough(done, color: .white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let supps = m.inlineSupps {
                    // Checkboxes live in the wheel: StackView's own AM/PM
                    // period buttons, not a generic "Open".
                    StackView(items: supps)
                } else {
                    if !m.detail.isEmpty {
                        Text(m.detail)
                            .font(.footnote.italic())
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !done { actionControl(m) }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Translucent so the thematic flow-field reads through; the
        // focused card sits a touch more solid + glows brighter so it
        // visibly "sings" at the centre of the wheel.
        .background(.ultraThinMaterial.opacity(focused ? 0.7 : 0.5))
        .background(.black.opacity(done ? 0.16 : (focused ? 0.30 : 0.24)))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(focused ? 0.9 : 0.42),
                                 accent.opacity(focused ? 0.35 : 0.14)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: focused ? 1.5 : 1)
        )
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(accent.opacity(done ? 0 : (focused ? 0.22 : 0.09)))
                .blur(radius: focused ? 22 : 12)
        )
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .opacity(done ? 0.62 : (m.isOutside ? 0.5 : 1))
    }

    @ViewBuilder
    private func actionControl(_ m: Moment) -> some View {
        switch m.action {
        case .toggle:       primaryButton("Mark done", m)
        case .startWorkout: primaryButton("Start →", m)
        case .openSheet:    primaryButton("Open", m)
        case .passive:      EmptyView()
        }
    }

    private func primaryButton(_ label: String, _ m: Moment) -> some View {
        Button { perform(m) } label: {
            Text(label)
                .font(.callout.monospaced().bold())
                .tracking(1.5)
                .foregroundStyle(m.band.accent)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(m.band.accent.opacity(0.5), lineWidth: 1))
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
            Text("Everything so far is done. Close the app.")
                .font(.footnote.italic())
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(.black.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
    }

    // MARK: - Actions

    private func perform(_ m: Moment) {
        switch m.action {
        case .toggle(let flip):
            let wasDone = m.isDone()
            flip()
            tick += 1
            if !wasDone { completedPulse += 1 }   // success haptic on complete
        case .startWorkout:         onStartWorkout()
        case .openSheet(let which): sheet = which
        case .passive:              break
        }
    }

    // MARK: - Moment construction

    private func isOutside(_ s: AuthorshipSurface) -> Bool {
        AuthorshipStore.get(s) == .outside
    }

    private func bandOrder(_ b: TimeBand) -> Int {
        switch b {
        case .morning:  return 0
        case .midday:   return 1
        case .workout:  return 2
        case .reachOut: return 3
        case .night:    return 4
        }
    }

    private func moments() -> [Moment] {
        var out: [Moment] = []
        func add(_ id: String, _ band: TimeBand, slot: Int, _ title: String,
                 _ detail: String, eventTime: Date? = nil,
                 inlineSupps: [Supplement]? = nil,
                 outside: Bool = false,
                 isDone: @escaping () -> Bool, _ action: Action) {
            out.append(Moment(id: id, band: band,
                               order: bandOrder(band) * 100 + slot,
                               title: title, detail: detail,
                               eventTime: eventTime, isDone: isDone,
                               action: action, inlineSupps: inlineSupps,
                               isOutside: outside))
        }

        // One Supplements card — renders StackView (the AM + PM
        // check-off period buttons) inline in the wheel so the boxes
        // are right there, not behind an "Open". Done = both periods.
        // Authorship NEVER removes the card (that hid it for users who
        // tagged it "from outside"); it only dims + un-focuses it.
        if let supps = bundle.profile?.supplement_stack, !supps.isEmpty {
            add("supps", .morning, slot: 0, "Supplements",
                "", inlineSupps: supps,
                outside: isOutside(.suppsAM),
                isDone: { DailyLock.isAMSuppsDone() && DailyLock.isPMSuppsDone() },
                .passive)
        }
        // Toggle cards carry NO subtext (hybrid contract): a clear act
        // + the toggle, nothing to read. Filler like "Morning routine."
        // restated the title and earned no decision.
        add("skin_am", .morning, slot: 1, "Skincare — AM", "",
            outside: isOutside(.skincareAM),
            isDone: { DailyLock.isSkincareAMDone() },
            .toggle { DailyLock.setSkincareAMDone(!DailyLock.isSkincareAMDone()) })
        add("mindful", .midday, slot: 0, "Eat mindfully",
            "One meal, no screen, attention on the food.",
            outside: isOutside(.mindful),
            isDone: { DailyLock.isMindfulEatingDone() }, .openSheet(.mindful))
        do {
            // The workout is the one card sitting on adaptive data
            // (traffic light, intensity Δ, swaps). Title = the session
            // identity ("Improv", "Yoga", "Push + core", "Rest day") —
            // the ACT, not "Train · Day N". Subtext = the adaptive
            // headline: how to show up at your limit today. On a Rest
            // day: the recovery note + no misleading "Start →".
            let sess = bundle.adapted_session
            let isRest = sess?.isRestDay ?? true
            let title = sess?.workoutTitle ?? "Train"
            let detail = sess?.workoutDetail ?? "Today's prescribed session."
            add("workout", .workout, slot: 0, title, detail,
                outside: isOutside(.workout),
                isDone: { DailyLock.isWorkoutDone() },
                isRest ? .passive : .startWorkout)
        }
        // EVENING band = "Reach out. Be in your body." (TimeBand
        // intent: connect + embodiment). It must never collapse to
        // nothing when social data is thin — so reach-out is always
        // present (named + why when we have a suggestion, a plain
        // prompt otherwise) and the embodiment half is always here.
        if let first = bundle.social?.reach_out?.first, let name = first.name {
            add("reach", .reachOut, slot: 0, "Reach out: \(name)",
                first.about_what ?? (first.days_since_last.map { "\($0)d since last" } ?? ""),
                isDone: { false }, .openSheet(.reachOut))
        } else {
            add("reach", .reachOut, slot: 0, "Reach out",
                "One message or call to someone who matters.",
                isDone: { false }, .openSheet(.reachOut))
        }
        // Embodiment — the body half of the evening. The rotating
        // prompt IS the act, so it's the title (toggle card → no
        // subtext per the contract). State is shared with
        // EmbodimentHintView through DailyLock.
        add("embodiment", .reachOut, slot: 1, EmbodimentHintView.dayPrompt.text, "",
            outside: isOutside(.embodiment),
            isDone: { DailyLock.isEmbodimentDone() },
            .toggle { DailyLock.setEmbodimentDone(!DailyLock.isEmbodimentDone()) })
        // (PM supplements are covered by the single Supplements card —
        // StackView shows both AM + PM period toggles.)
        add("skin_pm", .night, slot: 1, "Skincare — PM", "",
            outside: isOutside(.skincarePM),
            isDone: { DailyLock.isSkincarePMDone() },
            .toggle { DailyLock.setSkincarePMDone(!DailyLock.isSkincarePMDone()) })
        for (i, slot) in CustomSlotStore.load().enumerated() {
            let sid = slot.id
            add("custom_\(sid)", .night, slot: 2 + i, slot.fullName, "",
                isDone: { CustomSlotStore.isDone(slotID: sid) },
                .toggle { CustomSlotStore.toggle(slotID: sid) })
        }

        // Real calendar events — the ONLY moments that carry a clock
        // time. Slotted into whichever band their start hour falls in.
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for (i, ev) in (bundle.calendar ?? []).enumerated() {
            guard let s = ev.start,
                  let when = iso.date(from: s) ?? isoFrac.date(from: s) else { continue }
            if !Calendar.current.isDateInToday(when) { continue }
            let b = TimeBand.current(at: when)
            add("cal_\(i)", b, slot: 50 + i,
                ev.summary ?? "(event)", ev.location ?? "",
                eventTime: when, isDone: { false }, .passive)
        }

        return out.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return ($0.eventTime ?? .distantPast) < ($1.eventTime ?? .distantPast)
        }
    }

    /// Initial wheel position: the first pending moment in the current
    /// band, else the first pending moment overall, else the first card.
    private func pick(_ all: [Moment]) -> Moment? {
        let cur = TimeBand.current()
        let pending = all.filter { !$0.isDone() && !$0.isOutside }
        return pending.first { $0.band == cur }
            ?? pending.first
            ?? all.first { !$0.isOutside }
            ?? all.first
    }

    private func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mma"
        f.amSymbol = "am"; f.pmSymbol = "pm"
        return f.string(from: d)
    }
}

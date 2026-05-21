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
    @State private var showingClose = false
    @State private var scrollID: String?
    @State private var sheet: MomentSheet?
    /// Bumped when a moment is marked done — drives the success haptic.
    @State private var completedPulse = 0
    /// Foundation-Models-derived calendar load signal (PT, travel,
    /// surgery, race, etc). Re-computed when a new bundle arrives
    /// (keyed off `exported_at` so a within-session refresh re-runs).
    /// Nil while the first detection is in flight or when the calendar
    /// is empty.
    @State private var loadSignal: CalendarLoadDetector.Signal?

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
        // When set, the card renders a vertical list of toggle rows
        // (label + checkbox) inline — used by the Morning routine card
        // (supps_am + skin_am) and Evening routine card (supps_pm +
        // skin_pm + every custom slot). One combined card per band
        // replaces what used to be 2+ standalone toggle moments.
        var inlineRoutineRows: [RoutineRow]? = nil
        // True when its authorship surface is tagged "from outside".
        // Per Authorship.swift's design these stay VISIBLE (dim, and
        // not auto-focused) rather than disappearing from the wheel.
        var isOutside: Bool = false
        // Quiet-scaffold: dim + shrink the card until it's resolved
        // (workout card only — defaults keep every other card intact).
        var scaffolded: Bool = false
        // Render the inline WorkoutReconcileRow under the title/detail.
        var reconcile: Bool = false
    }

    /// One toggle row inside a combined "Morning routine" / "Evening
    /// routine" card. Each row is a label + optional sub-label (e.g.
    /// "5 items" for supps) + a tappable checkbox that flips the
    /// underlying DailyLock / CustomSlotStore state.
    private struct RoutineRow: Identifiable {
        let id: String
        let label: String
        let subLabel: String?       // small grey count / detail, optional
        let isOutside: Bool         // grey out if authorship == .outside
        let isDone: () -> Bool
        let toggle: () -> Void
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
        let mk = bundle.adapted_session?.week_makeup
        // dropped renders as an info line (no buttons) inside the
        // banner, so it does NOT gate showBanner. Authorship is iOS-only
        // (pipeline has no such signal) — suppress when workout=outside.
        let showBanner = mk != nil
            && !makeupAckStore.bool(forKey: makeupAckKey)
            && !isOutside(.workout)
        ZStack {
            VStack(spacing: 12) {
                if let mk, showBanner {
                    WeekMakeupBanner(makeup: mk,
                                     onKeep: { keepMakeup() },
                                     onUndo: { undoMakeup(mk) })
                }
                Group {
                    if all.isEmpty {
                        allClear
                    } else {
                        wheel(all)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if showingClose {
                DayCloseView(
                    rhythm: DayRhythm(now: Date(), closing: true),
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.4)) { showingClose = false }
                        tick += 1
                    }
                )
                .zIndex(1)
            }
        }
        .onAppear { if scrollID == nil { scrollID = pick(all)?.id } }
        // ONCE per actual calendar-day rollover — not on every band edge,
        // not on every scenePhase.active. The strict `.calendarDayChanged`
        // signal is posted by App.swift only when the date actually
        // changes (midnight while open, or first foreground after a date
        // change). The earlier wiring used `.dayDidRollOver`, which also
        // fires on band edges + every foreground, popping the close
        // overlay on every TimeBand transition.
        .onReceive(NotificationCenter.default.publisher(for: .calendarDayChanged)) { _ in
            withAnimation(.easeInOut(duration: 0.45)) { showingClose = true }
        }
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
        // Foundation Models calendar scan on every fresh bundle. The
        // detector is no-op on iOS < 26 / Apple Intelligence off — it
        // falls back to a keyword scan and still produces a Signal.
        // After detection we also write the signal up to the iCloud
        // inbox so the laptop pipeline's next refresh can fold it into
        // its rules (rule_calendar_load_taper in adaptive.py).
        .task(id: bundle.exported_at) {
            let signal = await CalendarLoadDetector.detect(from: bundle.calendar ?? [])
            loadSignal = signal
            if let signal {
                try? await iCloudTransport.shared.uploadCalendarSignal(signal)
            }
        }
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
                VStack(alignment: .leading, spacing: 12) {
                    Text(m.title)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .strikethrough(done, color: .white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let rows = m.inlineRoutineRows {
                        // Combined routine card (Morning / Evening) — the
                        // sub-items toggle inline so the user doesn't have
                        // to scroll through 3+ separate cards for the same
                        // band. No actionControl underneath — every row is
                        // its own toggle.
                        VStack(spacing: 8) {
                            ForEach(rows) { row in
                                routineRow(row, accent: accent)
                            }
                        }
                    } else if let supps = m.inlineSupps {
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
                // Quiet-scaffold: dim + shrink the (workout) card until
                // it's reconciled. Every other moment has scaffolded ==
                // false → opacity 1.0, full scale: untouched.
                .opacity(m.scaffolded ? 0.5 : 1.0)
                .scaleEffect(m.scaffolded ? 0.92 : 1.0, anchor: .leading)
                if m.reconcile {
                    Text("What did you do today?")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                    WorkoutReconcileRow(onResolved: { tick += 1 })
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
        // Whole-card tap target ONLY for the workout. The header comment
        // promises "the workout is always a card in the wheel and always
        // tappable to start" — without this, only the small "Start →"
        // button is hittable, and a tap on the card body does nothing.
        // We scope this to `.startWorkout` so toggle/openSheet cards keep
        // the explicit-button affordance (avoids accidental mark-done on
        // a stray tap during a scroll).
        .contentShape(Rectangle())
        .onTapGesture {
            if case .startWorkout = m.action, !done { perform(m) }
        }
    }

    /// A single sub-item row inside the combined routine card. Tap
    /// anywhere on the row to flip the underlying toggle. Outside-
    /// authored rows render dimmed (matching the card-level pattern).
    @ViewBuilder
    private func routineRow(_ r: RoutineRow, accent: Color) -> some View {
        let done = r.isDone()
        Button {
            r.toggle()
            tick += 1
            if !done { completedPulse += 1 }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(done ? accent : .white.opacity(0.55))
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .strikethrough(done, color: .white.opacity(0.5))
                    if let sub = r.subLabel, !sub.isEmpty {
                        Text(sub)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .opacity(r.isOutside ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
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
                 inlineRoutineRows: [RoutineRow]? = nil,
                 outside: Bool = false,
                 scaffolded: Bool = false, reconcile: Bool = false,
                 isDone: @escaping () -> Bool, _ action: Action) {
            out.append(Moment(id: id, band: band,
                               order: bandOrder(band) * 100 + slot,
                               title: title, detail: detail,
                               eventTime: eventTime, isDone: isDone,
                               action: action, inlineSupps: inlineSupps,
                               inlineRoutineRows: inlineRoutineRows,
                               isOutside: outside,
                               scaffolded: scaffolded, reconcile: reconcile))
        }

        // ── Morning routine ────────────────────────────────────────
        // One combined card per band (per user feedback "combine the
        // morning thing and combine evening things"). Morning collapses
        // what used to be two standalone moments (`supps` + `skin_am`)
        // into one card with two toggle rows. Each row is its own
        // checkbox; the card itself is `.passive` so taps go to the
        // rows, not a card-level button.
        let allSupps = bundle.profile?.supplement_stack ?? []
        let amSupps = allSupps.filter { !StackView.isEvening($0.timing) }
        let pmSupps = allSupps.filter {  StackView.isEvening($0.timing) }
        var morningRows: [RoutineRow] = []
        if !amSupps.isEmpty {
            morningRows.append(RoutineRow(
                id: "supps_am",
                label: "AM supps",
                subLabel: "\(amSupps.count) item\(amSupps.count == 1 ? "" : "s")",
                isOutside: isOutside(.suppsAM),
                isDone: { DailyLock.isAMSuppsDone() },
                toggle: { DailyLock.setAMSuppsDone(!DailyLock.isAMSuppsDone()) }
            ))
        }
        morningRows.append(RoutineRow(
            id: "skin_am",
            label: "Skincare — AM",
            subLabel: nil,
            isOutside: isOutside(.skincareAM),
            isDone: { DailyLock.isSkincareAMDone() },
            toggle: { DailyLock.setSkincareAMDone(!DailyLock.isSkincareAMDone()) }
        ))
        if !morningRows.isEmpty {
            add("morning_routine", .morning, slot: 0, "Morning routine", "",
                inlineRoutineRows: morningRows,
                // Card-level "from outside" only when EVERY row is — a
                // single outside-tagged sub-item shouldn't dim the whole
                // card; the row renders dimmed on its own.
                outside: morningRows.allSatisfy { $0.isOutside },
                isDone: { morningRows.allSatisfy { $0.isDone() } },
                .passive)
        }
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
            // Staleness guard. `adapted_session` is pinned by the
            // pipeline to whatever day refresh.sh last ran on (see
            // adaptive.todays_program_day). If the laptop didn't fire
            // overnight (WatchPaths-only, no inbox movement), it sits
            // on yesterday's program_day — and the card would render
            // yesterday's session as "today". When the pin disagrees
            // with iOS's actual weekday, fall back to today's slot in
            // `profile.daily_protocol` for the title + rest/train read,
            // and surface the staleness in the subtext so it's not silent.
            let todayKey = "Day \(NowFocusView.isoWeekdayNum())"
            let raw = bundle.adapted_session
            let pinned = (raw?.program_day ?? "")
            let isStale = !pinned.isEmpty && pinned != todayKey
            let todayProto = bundle.profile?.daily_protocol?[todayKey]
            let isRest: Bool
            let title: String
            let detail: String
            if isStale, let dp = todayProto {
                let presc = dp.session.trimmingCharacters(in: .whitespacesAndNewlines)
                isRest = presc.isEmpty || presc.lowercased() == "rest"
                title = isRest ? "Rest day" : AdaptedSession.titleFromPrescribed(presc)
                detail = "Plan stale (laptop last ran \(pinned)) — refresh to re-adapt."
            } else {
                isRest = raw?.isRestDay ?? true
                title = raw?.workoutTitle ?? "Train"
                let base = raw?.workoutDetail ?? "Today's prescribed session."
                // Foundation Models PT hint goes at the FRONT of detail so
                // it reads as the lede ("PT today — taper load. Green ·
                // full intensity"). On a rest day or when no PT context,
                // the base detail stands as-is. We intentionally do NOT
                // mutate intensity_modifier here — the pipeline is still
                // source of truth; the hint just tells the user why the
                // card should be read with one eye on the brake.
                if !isRest, let hint = CalendarLoadDetector.hint(loadSignal) {
                    detail = "\(hint) \(base)"
                } else {
                    detail = base
                }
            }
            let rhythm = DayRhythm()
            let unresolved = !rhythm.workoutResolved && !isOutside(.workout)
            let scaffold = unresolved
            let slotIdx = (rhythm.escalation == .pressing) ? -1 : 0
            add("workout", .workout, slot: slotIdx, title, detail,
                outside: isOutside(.workout),
                scaffolded: scaffold,
                reconcile: unresolved,
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
        // ── Evening routine ───────────────────────────────────────
        // The night-band sibling of "Morning routine" — PM supps,
        // Skincare PM, and every custom slot collapse into one card.
        // (Previously these were 2 standalone toggles + N custom-slot
        // moments; the wheel surfaced 3+ near-duplicate cards at night.)
        var eveningRows: [RoutineRow] = []
        if !pmSupps.isEmpty {
            eveningRows.append(RoutineRow(
                id: "supps_pm",
                label: "PM supps",
                subLabel: "\(pmSupps.count) item\(pmSupps.count == 1 ? "" : "s")",
                isOutside: isOutside(.suppsPM),
                isDone: { DailyLock.isPMSuppsDone() },
                toggle: { DailyLock.setPMSuppsDone(!DailyLock.isPMSuppsDone()) }
            ))
        }
        eveningRows.append(RoutineRow(
            id: "skin_pm",
            label: "Skincare — PM",
            subLabel: nil,
            isOutside: isOutside(.skincarePM),
            isDone: { DailyLock.isSkincarePMDone() },
            toggle: { DailyLock.setSkincarePMDone(!DailyLock.isSkincarePMDone()) }
        ))
        for slot in CustomSlotStore.load() {
            let sid = slot.id
            eveningRows.append(RoutineRow(
                id: "custom_\(sid)",
                label: slot.fullName,
                subLabel: nil,
                isOutside: false,
                isDone: { CustomSlotStore.isDone(slotID: sid) },
                toggle: { CustomSlotStore.toggle(slotID: sid) }
            ))
        }
        if !eveningRows.isEmpty {
            add("evening_routine", .night, slot: 1, "Evening routine", "",
                inlineRoutineRows: eveningRows,
                outside: eveningRows.allSatisfy { $0.isOutside },
                isDone: { eveningRows.allSatisfy { $0.isDone() } },
                .passive)
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
        if DayRhythm().escalation == .pressing,
           let w = all.first(where: { $0.id == "workout" }) {
            return w
        }
        let cur = TimeBand.current()
        let pending = all.filter { !$0.isDone() && !$0.isOutside }
        return pending.first { $0.band == cur }
            ?? pending.first
            ?? all.first { !$0.isOutside }
            ?? all.first
    }

    private var makeupAckKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "en_US_POSIX")
        return "week_makeup_ack_\(f.string(from: Date()))"
    }
    private var makeupAckStore: UserDefaults {
        UserDefaults(suiteName: "group.com.jlgao.PrefrontalCortex") ?? .standard
    }
    private func keepMakeup() {
        makeupAckStore.set(true, forKey: makeupAckKey)
        tick += 1
    }
    private func undoMakeup(_ mk: WeekMakeup) {
        DeviationUndo.submitSkipLockIn(weekday: mk.skipped?.first?.weekday)
        tick += 1
    }

    private func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mma"
        f.amSymbol = "am"; f.pmSymbol = "pm"
        return f.string(from: d)
    }

    /// ISO weekday: Mon=1 … Sun=7. Matches `daily_protocol` keys
    /// ("Day 1" = Monday) and `adaptive.todays_program_day()`.
    fileprivate static func isoWeekdayNum() -> Int {
        // Calendar.weekday returns Sun=1 … Sat=7; rotate to Mon=1 … Sun=7.
        let w = Calendar.current.component(.weekday, from: Date())
        return ((w + 5) % 7) + 1
    }
}

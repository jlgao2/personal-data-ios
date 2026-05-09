# Workout Loop v2 — auto-log, skip-with-friction, gamification

> **Status:** PROPOSAL · awaiting redline
> **Triggered by:** "auto pull workout data from apple health and log it, give me an option to skip workout, and make me select the skip workout button when I do, gameify it a bit"

## Why

Three coupled gaps in the daily loop:

1. **Effortful logging** — manual workout entry is the only way to get credit. If the Apple Watch already saw a 45-min cycle, you shouldn't have to also tap through `WorkoutSessionView`.
2. **No graceful exit** — there's no "I'm not training today" button. Days off look identical to days you forgot.
3. **No reward for showing up** — the daily check-ins (workout, supps, mindful eating) are work without texture. A small game layer makes the consistency visible and gives long-arc novelty.

Sub-project A of the four-way decomposition agreed in this brainstorming session (B = iCloud sync, C = on-device Claude, D = onboarding doc — all separate specs to follow).

## End-state — what the user does

```
Morning  → opens Now → DailyLockChip shows "○ ○ ○ ○ today"
                       (workout · AM supps · PM supps · mindful eating)
Cycles to work → Apple Watch records "Outdoor Cycling 38 min"
Foregrounds app → workout dot fills automatically: "● ○ ○ ○"
                  no manual log needed
Mid-day        → checks AM supps button → "● ● ○ ○"
Evening        → checks PM supps + mindful eating → "● ● ● ●"
                  → streak advances to 24 days
                  → "Tendril" achievement unlocks (if 30-day milestone hit)

If today is rest day OR you can't train:
  → long-press "skip today" link below the Start button (2.0s — the link
    fills with cyan as you hold)
  → reason sheet appears: Sick · Traveling · Busy · Unmotivated
                          · Injury · Scheduled rest
  → tap one → workout dot fills, source recorded, streak preserved
```

## Decisions locked in this brainstorm

| Decision | Choice |
|---|---|
| Streak anchor | **Full daily slam** — workout + AM supps + PM supps + mindful eating, all required |
| Game shape | **Streak number + ~12 achievements** (mix of milestone + behavior signals) |
| Skip friction | **Long-press 2.0s + pick reason from preset** |
| Skip reasons | Sick · Traveling · Busy · Unmotivated · Injury · Scheduled rest |
| Auto-log credit | **Either credits** — HK workout (≥10 min) OR manual session OR skip-with-reason. Both records flow into the spine. |
| Same-day cap | One credit per day even if multiple HK workouts |
| Rest day (Day 7) | Auto-credits workout slot if any HK movement OR a one-tap "rest acknowledged" affordance |
| Streak break | Quiet — no notification. Profile shows "starting over · N days was your last run" the next morning |
| Lock-screen controls | **Two-stage sequential**: 3 weight buttons (`−5` / `=` / `+5`) → tap one → widget refreshes → 3 rep buttons (`−1` / `=` / `+1`) → tap one → set logged + advance to next |

## Data model

### Per-day (UserDefaults, App Group)

| Key | Type | Source |
|---|---|---|
| `workout_done_<YYYY-MM-DD>` | Bool | NEW — set by HK pull, manual log finish, skip flow, or rest ack |
| `workout_source_<YYYY-MM-DD>` | String — `"hk"` \| `"manual"` \| `"skip"` \| `"rest_ack"` | NEW |
| `workout_skip_reason_<YYYY-MM-DD>` | String (one of the 6 presets) | NEW — only present when source = `skip` |
| `stack_period_<YYYY-MM-DD>_morning` | Bool | EXISTING |
| `stack_period_<YYYY-MM-DD>_evening` | Bool | EXISTING |
| `mindful_eat_<YYYY-MM-DD>` | Bool | EXISTING |

`DailyLock.isComplete(date:)` is the AND of all four. No separate persisted struct — it's a computed read across the existing key set.

### Streak state (single, App Group)

```swift
struct StreakState: Codable {
    var current: Int           // consecutive complete days, 0 if today incomplete & yesterday wasn't either
    var longest: Int
    var lastCompleteDate: String?  // YYYY-MM-DD
}
```
Key: `streak_state` (JSON-encoded).

Updated by `StreakState.refresh()` — called any time a daily-lock key changes. Logic:
1. Find longest run of consecutive complete days ending today or yesterday.
2. If yesterday was complete but today not yet, current = (yesterday's run length). The streak doesn't break until midnight of an incomplete day.
3. Update `longest = max(longest, current)`.

### Achievements (single, App Group)

```swift
struct AchievementState: Codable {
    var unlocked: [String: String]  // id → unlock date (YYYY-MM-DD)
}
```
Key: `achievement_state`.

Re-evaluated after any daily-lock change OR streak update. Newly-firing achievements get added with today's date and trigger a one-shot toast.

## Achievement catalog (12)

| id | name | condition | icon |
|---|---|---|---|
| `first_step` | First step | First-ever complete day | `figure.walk` |
| `week_of_work` | Week of work | 7-day streak | `7.circle` |
| `tendril` | Tendril | 30-day streak | `leaf` |
| `roots` | Roots | 90-day streak | `tree` |
| `pillar` | Pillar | 365-day streak | `building.columns` |
| `volume_keeper` | Volume keeper | 100 total complete days | `hexagon.fill` |
| `iron_line` | Iron line | 365 total complete days | `medal` |
| `honest_break` | Honest break | ≥3 skip-with-reason within any 30-day window | `hand.raised` |
| `bounce_back` | Bounce-back | Restarted a complete-day streak within 3 days of breaking | `arrow.uturn.up` |
| `quiet_rest` | Quiet rest | 4 consecutive Sunday rest days acknowledged | `moon.stars` |
| `mindful_month` | Mindful month | 30-day mindful-eating streak (own track) | `eye.circle` |
| `clean_week` | Clean week | Full week (Mon-Sun) of supps both AM and PM checked | `checkmark.seal` |

Conditions are pure functions of `(today: Date, dailyLockHistory: [Date: DailyLock], streak: StreakState)` returning `Bool`. Easy to unit-test if a future iOS test target lands.

## UI surfaces

### Now tab — `DailyLockChip` (new)

A row of 4 dots with labels, sits between TimelineView and StackView (or replaces the redundant top breathing-room padding). Each dot fills cyan when its slot is complete.

```
   ⓦ   ⓢa  ⓢp  ⓜ        (4 dots, cyan if filled, dim if pending)
   ───────────────         (a thin progress line behind, fills 0→full)
   24 days running         (small italic if streak ≥ 7)
```

Tapping the chip expands to a small detail showing exact status of each slot (workout source, time supps were checked, etc.).

### Now tab — `AdaptedSessionView` gains `SkipWorkoutButton`

Below the existing "START →" pill on the header row, a small low-contrast text link:

```
[ START → ]                    ← the existing big pill
skip today                     ← new, small italic, .white.opacity(0.4)
```

Long-press it: a cyan fill animates left-to-right behind the text over 2.0 s. Release before completion → cancels. Held to completion → haptic + `SkipReasonSheet` slides up.

### `SkipReasonSheet` (new)

PresentationDetent `.medium`. Six chip buttons in a wrapped grid:

```
   ┌─────────┐  ┌──────────────┐  ┌──────┐
   │  Sick   │  │  Traveling   │  │ Busy │
   └─────────┘  └──────────────┘  └──────┘
   ┌─────────────┐  ┌──────────┐  ┌────────────────┐
   │ Unmotivated │  │  Injury  │  │ Scheduled rest │
   └─────────────┘  └──────────┘  └────────────────┘
```

Tap a chip → record + dismiss + workout dot fills + soft success haptic.

### Profile tab — `StreakChip` + `AchievementGrid` (new)

Top of Profile, just under the gear:

```
┌─────────────────────────────┐
│  🔥  24 day streak           │  ← StreakChip
│      best: 47                │
└─────────────────────────────┘

ACHIEVEMENTS                        ← caption
┌──┬──┬──┬──┐
│●│○│●│○│                          ← AchievementGrid, 4 cols × 3 rows
├──┼──┼──┼──┤
│●│●│●│○│
├──┼──┼──┼──┤
│○│○│●│○│
└──┴──┴──┴──┘
```

Filled = unlocked (cyan icon). Empty = locked (grey outline). Tap any → small detail sheet with name, description, condition, unlock date if applicable.

### `AchievementUnlockToast` (new)

When a new achievement fires (during `refresh()` after a daily-lock change), overlay a centered toast for ~2 s with icon + name + "achievement unlocked" caption. Soft `.symbolEffect(.bounce)` on the icon. Dismisses on tap or auto-fades.

## HealthKit auto-pull

### `SampleExporter.fetchTodayWorkouts()` (new method)

Queries `HKWorkoutType.workoutType()` for samples with `startDate >= today.startOfDay`.
Filters: `workout.duration >= 600` (10 min).
Maps each to a session row:
```swift
[
    "client_id": "hk-\(yyyyMMdd)-\(workout.workoutActivityType.rawValue)",
    "ts": ISO8601(workout.startDate),
    "sport": workout.workoutActivityType.name,  // mapped to canonical name
    "duration_min": workout.duration / 60,
    "rpe": NSNull(),  // unknown from HK
    "note": "auto-logged from HealthKit",
]
```

If any qualifying workout exists today → `DailyLock.setWorkoutDone(source: .hk)`.

POSTs all qualifying rows via `TransportClient.uploadSessions` (silent best-effort if transport not configured).

### When it runs

- `AppStore.bootstrap()` — first launch
- `AppStore.refreshOnForeground()` — on every scenePhase → `.active`
- Pull-to-refresh on Now

### Dedupe

`client_id` is deterministic per (date, sport), so re-running the pull doesn't create duplicates. The pipeline-side `parsers/ios_sessions.py` already merges by `client_id`. No code changes needed there.

### Permission

`NSHealthShareUsageDescription` already in `Info.plist` (existing). New: read `HKWorkoutType` — request permission in `HealthStore.authorize()` alongside the existing types.

## Skip-with-friction flow

Implementation sketch for the `SkipWorkoutButton`:

```swift
struct SkipWorkoutButton: View {
    @State private var pressProgress: Double = 0
    @State private var showReasonSheet = false
    private let holdDuration: Double = 2.0

    var body: some View {
        ZStack {
            // background fill that grows with press
            GeometryReader { geo in
                Capsule()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: geo.size.width * pressProgress)
                    .animation(.linear(duration: 0.05), value: pressProgress)
            }
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                Text("skip today")
            }
            .font(.caption2.italic())
            .foregroundStyle(.white.opacity(0.4))
            .padding(.vertical, 6).padding(.horizontal, 10)
        }
        .gesture(
            LongPressGesture(minimumDuration: holdDuration)
                .onEnded { _ in
                    pressProgress = 1
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showReasonSheet = true
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if pressProgress < 1 {
                        withAnimation(.linear(duration: holdDuration)) {
                            pressProgress = 1
                        }
                    }
                }
                .onEnded { _ in
                    if pressProgress < 1 {
                        withAnimation(.easeOut(duration: 0.2)) { pressProgress = 0 }
                    }
                }
        )
        .sheet(isPresented: $showReasonSheet) {
            SkipReasonSheet { reason in
                DailyLock.setWorkoutDone(source: .skip, reason: reason)
                StreakState.refresh()
                Achievements.refresh()
            }
            .presentationDetents([.medium])
        }
    }
}
```

(Implementation details refine in the plan; the gesture behavior may need tuning to feel right — the SwiftUI long-press + simultaneous drag pattern is the standard way to get a fillable hold.)

## Lock-screen interactive controls

WidgetKit (iOS 17+) only allows `Button` and `Toggle` interactivity on widgets — no swipe, no slider, no drag, no text input. Each tap fires an `AppIntent`. Lock-screen rectangle is ~150×60pt; comfortably fits 3 buttons in a row + a small status line above.

**Design: two-stage sequential.** The widget shows different buttons depending on which "stage" of the next set you're in:

```
Stage 1 (pick weight delta):
┌──────────────────────────────────────┐
│ SET 3/5 · last 135 × 10              │
│  WEIGHT       [−5]  [=]  [+5]        │
└──────────────────────────────────────┘

→ tap a weight button (stages the weight, advances to stage 2)

Stage 2 (pick rep delta):
┌──────────────────────────────────────┐
│ SET 3/5 · staged 140 × ?             │
│  REPS         [−1]  [=]  [+1]        │
└──────────────────────────────────────┘

→ tap a rep button (commits set + advances to next set's stage 1)
```

**Two taps per set on the lock screen, one set advance per cycle.** All state mutations happen via `AppIntent` calls; the widget's `Provider.getTimeline` re-reads App Group state on each refresh and renders the correct stage.

### App Group state — `LockScreenWorkoutState`

```swift
struct LockScreenWorkoutState: Codable {
    var inProgress: Bool             // false when no workout active → widget shows NextUp instead
    var exerciseKey: String          // current exercise's stable key
    var exerciseName: String         // user-facing label
    var setIndex: Int                // 0-based; the set you're about to log
    var totalSets: Int               // for the "SET N/M" readout
    var lastWeight: Double           // baseline for `=` and the delta math
    var lastReps: Int
    var stage: Stage                 // .weight or .reps — which buttons to show
    var stagedWeight: Double?        // set during stage transition; nil at stage 1
    var mode: Mode                   // .free | .band | .time | .amrap
    var bandColor: String?           // for band mode
    var unit: String                 // "lb" | "kg"

    enum Stage: String, Codable { case weight, reps }
    enum Mode: String, Codable { case free, band, time, amrap }
}
```

Persisted at `widget_workout_state.json` in the App Group container, written by `WorkoutSessionView` on every focus / preset-tap, written by the AppIntents on every lock-screen tap, read by the widget's TimelineProvider on every render.

### AppIntents

Two intents in a shared module visible to both the host app and the widget extension:

```swift
struct StageWeightDeltaIntent: AppIntent {
    static var title: LocalizedStringResource = "Stage weight"
    @Parameter(title: "Delta") var delta: Double      // -5, 0, +5

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        guard state.inProgress, state.stage == .weight else { return .result() }
        state.stagedWeight = max(0, state.lastWeight + delta)
        state.stage = .reps
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadTimelines(ofKind: WorkoutLockWidget.kind)
        return .result()
    }
}

struct CommitRepDeltaIntent: AppIntent {
    static var title: LocalizedStringResource = "Commit set"
    @Parameter(title: "Rep delta") var delta: Int     // -1, 0, +1

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        guard state.inProgress, state.stage == .reps,
              let weight = state.stagedWeight else { return .result() }
        let reps = max(0, state.lastReps + delta)

        // Persist into the in-progress workout's per-set storage,
        // mirroring what WorkoutSessionView.markComplete does.
        WorkoutProgress.completeSet(exerciseKey: state.exerciseKey,
                                    setIndex: state.setIndex,
                                    weight: weight, reps: reps)

        // Advance to next set (or next exercise) and reset to stage 1.
        state.setIndex += 1
        if state.setIndex >= state.totalSets {
            // Exercise complete — advance to next exercise OR end workout.
            advanceToNextExercise(&state)
        }
        state.stage = .weight
        state.stagedWeight = nil
        state.lastWeight = weight
        state.lastReps = reps
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadTimelines(ofKind: WorkoutLockWidget.kind)
        return .result()
    }
}
```

### Mode-specific button layouts

| Mode | Stage 1 (weight) | Stage 2 (reps) |
|---|---|---|
| **Free weight** | `−5` `=` `+5` | `−1` `=` `+1` |
| **Band** (color cycle, no numeric weight) | `← prev` `=` `next →` (cycles through 5 BandColor cases) | `−1` `=` `+1` |
| **Time** (mobility holds — no rep concept) | (skipped — single-stage) | `−5s` `=` `+5s` |
| **AMRAP** (bodyweight, fluid reps) | (skipped if `lastWeight == 0`) | `−1` `=` `+1` |

For modes that skip stage 1, the widget jumps straight to stage 2 and a single tap commits.

### Widget — `WorkoutLockWidget`

New widget kind `PrefrontalCortexWorkoutLock`, registered alongside the existing `HeroWidget` / `SessionWidget` / `ReachOutWidget` / `NextUpWidget` in `PrefrontalCortexWidgetBundle`.

Supported families:
- `accessoryRectangular` — primary lock-screen surface
- `systemSmall` — mirror on home screen for quick mid-set tapping at the rack

`accessoryInline` and `accessoryCircular` are intentionally skipped — too small for any usable button cluster.

### "No workout in progress" fallback

When `LockScreenWorkoutState.inProgress == false`, the widget renders the same content as `NextUpWidget` (next chronological item). This way the user only needs ONE lock-screen widget; it morphs from "what's next today" into "log your set" when a workout starts and back when it ends.

Implementation-wise, the WorkoutLockWidget's view branches on the in-progress flag.

### Workout start / end transitions

- **Start**: `WorkoutSessionView.onAppear` writes `inProgress = true` + initial state (set 0, exercise's first item, lastWeight from memory, etc.) and triggers `WidgetCenter.shared.reloadAllTimelines()`.
- **Manual end**: `WorkoutSessionView.commitAndDismiss()` writes `inProgress = false`. Widget reverts to NextUp mode.
- **Auto end**: when the last exercise's last set is committed via the lock-screen intent, the intent itself sets `inProgress = false`.

### Why two-stage instead of single-button or 6-button-grid

- **Single button** (option α' from brainstorm) is too rigid — you'd never adjust on the lock screen, just always log "same." That's fine 70% of the time but punishes deviation.
- **6 buttons simultaneous** (option α) is feasible but the rectangle is small enough that 6 chip buttons + a status readout becomes hard to read and easy to mis-tap. Reasonable people would disagree here; we picked sequential to keep readability.
- **Two-stage sequential** (chosen) doubles taps but keeps each stage decision atomic + the buttons big enough to reliably hit. The widget refresh between stages is fast (App Group state + WidgetCenter reload).

## File structure

### NEW (iOS — main app)

| Path | Responsibility |
|---|---|
| `PrefrontalCortex/Game/DailyLock.swift` | Wrapper around per-day UserDefaults keys; `isComplete(date:)`, `setWorkoutDone(source:reason:)`, etc. |
| `PrefrontalCortex/Game/StreakState.swift` | `current`, `longest`, `lastCompleteDate`. `refresh()` recomputes from history. Persists in App Group. |
| `PrefrontalCortex/Game/Achievements.swift` | 12 achievement definitions + condition evaluators. `refresh()` returns newly-unlocked ids. Persists in App Group. |
| `PrefrontalCortex/Views/DailyLockChip.swift` | The 4-dot Now-tab indicator. |
| `PrefrontalCortex/Views/SkipWorkoutButton.swift` | Low-contrast hold-to-fill text link below the Start pill. |
| `PrefrontalCortex/Views/SkipReasonSheet.swift` | Modal with the 6 reason chips. |
| `PrefrontalCortex/Views/StreakChip.swift` | Current streak chip on Profile. |
| `PrefrontalCortex/Views/AchievementGrid.swift` | 4×3 grid on Profile + per-achievement detail sheet. |
| `PrefrontalCortex/Views/AchievementUnlockToast.swift` | Center overlay shown when a new achievement fires. |

### NEW (shared / widget extension — lock-screen controls)

| Path | Responsibility |
|---|---|
| `PrefrontalCortexShared/LockScreenWorkoutState.swift` | Codable struct + `LockScreenWorkoutStore` (load/save to App Group container). Visible to both the host app and the widget extension. |
| `PrefrontalCortexShared/WorkoutAppIntents.swift` | `StageWeightDeltaIntent` and `CommitRepDeltaIntent` (+ `BandColorCycleIntent` for band-mode stage 1). `AppIntent` conformance lives in shared scope so the widget's `Button(intent:)` can fire them. |
| `PrefrontalCortexWidget/WorkoutLockWidget.swift` | The new widget. TimelineProvider reads `LockScreenWorkoutState` from App Group; view branches on `inProgress` (active workout → stage-aware button cluster, idle → NextUp fallback). Registered in `PrefrontalCortexWidgetBundle`. |

### MODIFIED (iOS)

| Path | Change |
|---|---|
| `HealthKit/SampleExporter.swift` | Add `fetchTodayWorkouts()`; extend `dailySamples()` to also collect HK workouts via `HKWorkoutType` query. |
| `HealthKit/HealthStore.swift` | Add `HKObjectType.workoutType()` to authorization request. |
| `AppStore.swift` | On `bootstrap` + `refreshOnForeground`: call `SampleExporter.fetchTodayWorkouts()`, then `StreakState.refresh()`, then `Achievements.refresh()`. Surface unlocked-toast via `lastUploadResult`-style overlay. |
| `ContentView.swift` | Insert `DailyLockChip` near top of Now's content; add `StreakChip` + `AchievementGrid` to Profile tab. Wire achievement-unlock toast overlay. |
| `Views/AdaptedSessionView.swift` | Place `SkipWorkoutButton` below the Start pill row. |
| `Views/StackView.swift` | After `toggle(period:)`, call `StreakState.refresh()` + `Achievements.refresh()`. |
| `Views/MindfulEatingTodayView.swift` | After `toggle()`, same hooks. |
| `Views/WorkoutSessionView.swift` | On `commitAndDismiss()`, call `DailyLock.setWorkoutDone(source: .manual)` so the workout slot fills. **Plus**: `onAppear` writes initial `LockScreenWorkoutState`; `markComplete` mirrors the same state mutations the lock-screen AppIntents perform; `commitAndDismiss` flips `inProgress = false`. After every state write, calls `WidgetCenter.shared.reloadTimelines(ofKind: WorkoutLockWidget.kind)`. |
| `WidgetSnapshotWriter.swift` | Add `streak_current` + `streak_longest` to the snapshot for the existing widgets to surface (HeroWidget can render the streak; deferred). |
| `PrefrontalCortexWidget/PrefrontalCortexWidgetBundle.swift` | Register `WorkoutLockWidget()` alongside the existing four. |

### Pipeline (no changes)

Auto-pulled HK workouts flow through the existing `/v1/sessions` → `parsers/ios_sessions.py` → events parquet path. `client_id="hk-..."` distinguishes them in queries.

## Streak-break handling

On `StreakState.refresh()`:
- Walk back from today, counting consecutive complete days
- If today is not yet complete: current = consecutive run ending yesterday
- If today IS complete: current = consecutive run ending today
- If gap of ≥ 1 day: streak resets

When current resets to 0 (after being non-zero), record `lastBreak: Date` + the prior `current` value. Profile tab's StreakChip on next morning shows: `"starting over · 23 days was your last run"` until a new streak ≥ 1 begins.

No notification. No banner on Now. Quiet by design — mistakes shouldn't punish.

## What's out of scope for v1

- **Streak rendering inside `HeroWidget`** — the snapshot includes streak data so the existing widgets *could* show it, but the explicit addition is deferred. The new `WorkoutLockWidget` is the only added widget in v1.
- **Lock-screen rest timer** — between-set countdown. Out — adds AppIntent + animation complexity that doesn't pay off until usage data shows people want it.
- **Lock-screen end-workout button** — must end the workout via the in-app `Done`. Avoids fat-fingering an end during a set.
- **Multi-exercise auto-advance on lock screen** — when an exercise's sets are all logged, the widget advances to the next exercise's stage 1 automatically; no UI for *jumping back* to a prior exercise from the lock screen (do that in-app).
- **Sharing achievements** — no social.
- **Custom/user-authored achievements** — the 12 are fixed in code.
- **Progress bars on locked achievements** — binary unlocked/locked only. "Halfway to Tendril" affordance is a follow-up.
- **Notification when streak might break** — e.g. evening reminder if not yet complete. Out — quiet by design for v1.
- **Per-domain streaks** ("supps streak," "eating streak") — only the unified streak in v1. The mindful-eating chip already shows its own 7-day count, that stays.
- **Streak freeze / vacation pause** — a Duolingo-style "freeze" preserve. Deferred. The skip-with-reason mechanism partially covers this for workouts.

## Migration / first-run

- First open after install: all daily-lock keys empty → today shows 4 unfilled dots, streak = 0.
- HK workout pull asks for `HKObjectType.workoutType()` permission (in addition to existing types).
- No backfill — past days that were "complete" by manual definition aren't retro-counted. Streak starts fresh from today. This is intentional; keeps the data model simple and the user starts the new game cleanly.

## Open questions resolved with sensible defaults (redline if you want)

- **Long-press duration**: 2.0 s
- **HK workout minimum duration**: 10 min
- **Reason picker**: Sick · Traveling · Busy · Unmotivated · Injury · Scheduled rest
- **Day 7 (Sunday) auto-credit**: yes if any HK movement, else one-tap "rest acknowledged" affordance under the Skip button
- **Achievement grid size**: 4 columns × 3 rows on Profile
- **Streak chip placement**: top of Profile, just under the gear icon overlay
- **Daily-lock chip placement**: between TimelineView and StackView on Now
- **Toast duration**: 2.0 s; tap to dismiss

## Self-review checklist

- **Spec coverage:** Each user-asked feature has a section: auto-log → "HealthKit auto-pull"; skip-with-friction → "Skip-with-friction flow" + button impl sketch; gameify → "Achievement catalog" + "UI surfaces" + "Streak state"; lock-screen interactivity → "Lock-screen interactive controls" with two-stage AppIntent design. ✓
- **Placeholder scan:** No real placeholder text. All knobs (long-press 2s, HK 10 min, button counts, color list, achievement count) have concrete defaults. ✓
- **Internal consistency:** DailyLock keys match between Data Model and File Structure. The 4 dots in DailyLockChip correspond to the 4 fields in `isComplete`. The `LockScreenWorkoutState` modes mirror the in-app `ParsedExercise` modes (free / band / time / amrap). The lock-screen Stage 1 / Stage 2 mirror the in-app weight cluster + rep cluster. The button counts (3 + 3) are explicit per mode. ✓
- **Scope check:** Single sub-project (sub-project A of the four-way decomposition). Bounded to iOS + WidgetSnapshotWriter additions + a new widget extension entry. ✓
- **Ambiguity check:** "Either credits" is concrete (HK ≥10 min OR manual log finish OR skip-with-reason OR rest ack); same-day cap is one-credit. Skip-with-friction is 2.0s long-press + reason picker. Lock-screen interaction is two-stage sequential, 3 buttons each, with explicit per-mode mapping. ✓

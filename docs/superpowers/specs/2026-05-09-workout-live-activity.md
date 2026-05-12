# Workout Live Activity — auto-appearing lock-screen + Dynamic Island session

> **Status:** PROPOSAL · awaiting redline
> **Triggered by:** "i mean a notification with interactive elements when I start the workout?" — the workout-loop v2 lock-screen widget requires a one-time install via the lock-screen customizer. This spec adds a Live Activity (ActivityKit) so the same set-logging buttons appear automatically when a workout starts, without any setup, and dismiss themselves when the workout ends.

## Why

Three gaps left over from workout-loop v2:

1. **The lock-screen widget needs to be installed.** Most users won't go to Customize → pick the rectangle. If they do, it stays there forever — competing for the one-or-two precious lock-screen widget slots. A Live Activity is ephemeral: present only during the session.
2. **No Dynamic Island presence.** On iPhone 14 Pro+, the always-on island is the right place for "you're mid-set" status. Today's widget doesn't reach it.
3. **Notifications can't carry interactive buttons** in the way the user wants. `UNNotificationAction` only fires when you swipe-to-reveal; Live Activity buttons (iOS 17+) tap directly through `AppIntent`, exactly like the widget already does.

The Live Activity reuses 100% of the widget's button cluster + `WorkoutAppIntents` — it's a new presentation surface, not a new state machine.

## End-state — what the user does

```
Open app → start workout
  → Live Activity appears INSTANTLY on lock screen + Dynamic Island.
    No customization needed. Same 3-button row as the rectangular widget.

Lock phone, walk to rack:
  Lock screen shows:
  ┌──────────────────────────────────────┐
  │  ● Prefrontal Cortex                 │
  │  SET 2/5 · BENCH PRESS               │
  │  staged 140 × ?                       │
  │   [−1]    [=]    [+1]                │
  └──────────────────────────────────────┘

Dynamic Island compact:  ●●● 2/5
Dynamic Island expanded: full set readout + 3 buttons
                         (long-press the island to expand)

Tap a button on lock screen or island → set commits, activity refreshes,
  next set's stage 1 (weight) appears, ready for the next two taps.

Last set committed → activity stale-flashes "Workout complete · tap to log notes",
  auto-dismisses after 30s OR on next foreground.

Manually end workout in app → activity ends immediately.
```

The existing rectangular widget stays — it's the "ambient default" for users who want it pinned. The Live Activity is the "auto-appearing" overlay during sessions. They share state (`LockScreenWorkoutState`) and intents (`WorkoutAppIntents`) so behavior is identical.

## Decisions locked

| Decision | Choice |
|---|---|
| Mechanism | **ActivityKit Live Activity** with `ActivityAttributes`, NOT `UNUserNotification`. UNN buttons require swipe-to-reveal + can't update mid-life; LA renders inline + updates via `Activity.update()`. |
| Started by | `WorkoutSessionView.onAppear` — same hook that today writes `LockScreenWorkoutState.inProgress = true`. Adds one line: `WorkoutLiveActivity.start(state:)`. |
| Ended by | `WorkoutSessionView.commitAndDismiss` + the `CommitRepDeltaIntent` when `setIndex == totalSets - 1` and last exercise. Calls `WorkoutLiveActivity.end()`. |
| State source | Reads the SAME App-Group `LockScreenWorkoutState` the widget reads. No second source of truth. |
| Updates | Push-free (local). Every `WorkoutAppIntents.perform()` calls `WorkoutLiveActivity.refresh()` after persisting state, mirroring what it already does for `WidgetCenter.reloadTimelines`. |
| Buttons | Same `lockButton` chip cluster from the widget, reused via a shared SwiftUI view extracted into `PrefrontalCortexShared/`. |
| Dynamic Island compact | Dot-row `setIndex/totalSets` indicator + exercise initial. |
| Dynamic Island expanded | Full set readout + 3-button row + small "End" button (which the lock-screen widget intentionally lacks — island has more vertical room and the user is actively engaging it). |
| Lock-screen variant | Single rectangle, identical content shape to the widget so muscle memory transfers. |
| Authorization | Live Activities are opt-in via Settings → Notifications → Allow Live Activities. App requests `ActivityAuthorizationInfo().areActivitiesEnabled` check on first start; falls back to a one-time inline banner pointing the user to Settings if disabled. No push token needed (push updates are out of scope). |
| Stale state | When `inProgress` flips to false, `Activity.end(dismissalPolicy: .after(Date() + 30s))` so the user can still see the last completed set briefly. Manual dismissal also works. |
| iOS version | iOS 17+ required (interactive buttons in Live Activities are 17+). Workout-loop v2 already targets iOS 17+, so no new floor. |

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│  PrefrontalCortexShared (already exists)                   │
│  ─ LockScreenWorkoutState                  (single source) │
│  ─ WorkoutAppIntents                       (single source) │
│  ─ WorkoutSetButtonRow  ← NEW (extracted from widget)      │
│  ─ WorkoutLiveActivityAttributes  ← NEW                    │
└────────────────────────────────────────────────────────────┘
                ▲                              ▲
                │                              │
   ┌────────────┴───────────┐    ┌─────────────┴──────────────┐
   │  PrefrontalCortexWidget │    │  PrefrontalCortex (host)   │
   │  ─ WorkoutLockWidget    │    │  ─ WorkoutLiveActivity     │
   │   (renders SetButtonRow)│    │   (start/update/end API)   │
   │  ─ WorkoutLiveActivity  │    │  ─ WorkoutSessionView      │
   │   View (renders         │    │     calls .start/.end       │
   │   SetButtonRow inside    │    │  ─ AppStore checks auth     │
   │   ActivityConfiguration) │    └────────────────────────────┘
   └────────────────────────┘
```

The Live Activity's UI must be declared in the widget extension (Apple requirement: `ActivityConfiguration` lives next to widgets). The host app uses `Activity.request/.update/.end` to drive it. Both reach the same `LockScreenWorkoutStore` via App Group.

## Data model

### `WorkoutLiveActivityAttributes` (new — shared module)

```swift
import ActivityKit

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    /// Static for the lifetime of the activity.
    let workoutStartedAt: Date
    let workoutTitle: String     // e.g. "Day 4 · Back/Biceps"

    /// Mutable per-set state mirrored from LockScreenWorkoutState.
    /// Kept small — Apple caps ContentState payload at 4KB.
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var setIndex: Int
        var totalSets: Int
        var lastWeight: Double
        var lastReps: Int
        var stage: String          // "weight" | "reps"
        var stagedWeight: Double?
        var mode: String           // "free" | "band" | "time" | "amrap"
        var bandColor: String?
        var unit: String
        var isComplete: Bool       // true on the final-set transition; drives auto-dismiss styling
    }
}
```

`ContentState` is a strict subset of `LockScreenWorkoutState` — every field except `inProgress` (which is implicit while the activity is alive). A small adapter `ContentState.from(_ state: LockScreenWorkoutState)` keeps them in sync.

### Lifecycle

| Event | Action |
|---|---|
| `WorkoutSessionView.onAppear` | If `Activity<...>.activities.isEmpty`, request a new one with current state. |
| Every `WorkoutAppIntents.perform()` | After `LockScreenWorkoutStore.save`, call `WorkoutLiveActivity.refresh()` which finds the current activity and `await activity.update(.init(state: ..., staleDate: nil))`. |
| Final set committed | `state.isComplete = true`; `Activity.end(.init(state: ..., staleDate: nil), dismissalPolicy: .after(.init(timeIntervalSinceNow: 30)))`. |
| `WorkoutSessionView.commitAndDismiss` | `WorkoutLiveActivity.endAll(immediate: true)`. |
| App reopen with stale activity | `AppStore.bootstrap` ends any orphaned activity whose `workoutStartedAt` is > 4h old (defensive). |

## File structure

### NEW (shared)

| Path | Responsibility |
|---|---|
| `PrefrontalCortexShared/WorkoutLiveActivityAttributes.swift` | The `ActivityAttributes` type + `ContentState` + `from(_:)` adapter. |
| `PrefrontalCortexShared/WorkoutSetButtonRow.swift` | Extracted shared SwiftUI view. The widget AND the Live Activity render this. Takes `(state, layout: .compactLockScreen / .island)` for tiny per-surface tweaks. |

### NEW (widget extension — UI declaration)

| Path | Responsibility |
|---|---|
| `PrefrontalCortexWidget/WorkoutLiveActivityView.swift` | The `ActivityConfiguration` declaration. Three regions: lock-screen view, Dynamic Island (compact leading + compact trailing + minimal + expanded), all built from `WorkoutSetButtonRow` + small per-region wrappers. Registered in `PrefrontalCortexWidgetBundle`. |

### NEW (host app — lifecycle)

| Path | Responsibility |
|---|---|
| `PrefrontalCortex/LiveActivity/WorkoutLiveActivity.swift` | Static facade: `start(state:title:)`, `refresh()`, `end(immediate:)`, `endAll()`. Internally walks `Activity<WorkoutLiveActivityAttributes>.activities`. Handles `areActivitiesEnabled` check + first-run banner trigger. |
| `PrefrontalCortex/Views/LiveActivityDisabledBanner.swift` | One-time banner shown above the Start pill if `areActivitiesEnabled == false`. Tapping deep-links to Settings via `UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!)`. Dismissable; persists `liveActivity_banner_dismissed_v1` flag. |

### MODIFIED

| Path | Change |
|---|---|
| `project.yml` | Already has the widget + shared targets. Add `ActivityKit.framework` to host-app target's link flags. (Widget extension already gets it via WidgetKit transitively, but explicit is safer.) |
| `PrefrontalCortex/Resources/Info.plist` | Add `NSSupportsLiveActivities: true`. |
| `PrefrontalCortex/Views/WorkoutSessionView.swift` | `onAppear` after the existing `LockScreenWorkoutStore.save`: `WorkoutLiveActivity.start(state: ..., title: dayKey + " · " + exerciseGroup)`. `commitAndDismiss`: add `WorkoutLiveActivity.endAll(immediate: true)` after `LockScreenWorkoutStore.clear()`. |
| `PrefrontalCortexShared/WorkoutAppIntents.swift` | After every `LockScreenWorkoutStore.save(state)`, also call `WorkoutLiveActivity.refresh()`. (Cross-target dependency — the facade is host-app-only, so the intent calls a small protocol-bridged version OR the refresh is moved into the shared module via a thin wrapper that re-imports `Activity` directly. Concrete pattern: put `WorkoutLiveActivityRefresher.refresh()` in the shared module — it's just `for activity in Activity<...>.activities { await activity.update(...) }`, no host-app dependency.) |
| `PrefrontalCortex/AppStore.swift` | On `bootstrap`: orphan-cleanup pass that ends any Live Activity whose `workoutStartedAt > 4h ago`. |
| `PrefrontalCortexWidget/PrefrontalCortexWidgetBundle.swift` | Add `WorkoutLiveActivityConfiguration()` to the bundle body alongside the existing widgets. |
| `PrefrontalCortexWidget/WorkoutLockWidget.swift` | Refactor: extract `buttonRow(for:)` body into `WorkoutSetButtonRow` (shared) and call it from both surfaces. No behavior change. |

### Pipeline

No changes. Live Activity is presentation-only; sets still flow through the existing `WorkoutProgress.completeSet` → eventual sync path.

## UI specs

### Lock-screen view (`accessoryRectangular`-equivalent surface)

```
┌──────────────────────────────────────────────┐
│  ● Prefrontal Cortex                         │  ← .activitySystemActionForegroundColor
│  SET 2/5 · BENCH PRESS                       │  ← caption.monospaced, cyan
│  staged 140 × ?                              │  ← caption.monospaced, white 70%
│   [−1]      [=]      [+1]                    │  ← WorkoutSetButtonRow(.compactLockScreen)
└──────────────────────────────────────────────┘
```

Identical content shape to `WorkoutLockWidget.activeView`. The container is `.containerBackground(.black, for: .widget)` (matches the widget) so the lock-screen treatment is consistent whether the user pinned the widget or has only the activity visible.

### Dynamic Island

**Compact** (the always-on slim version):
- Leading: dot-row of `totalSets` dots, filled up to `setIndex`
- Trailing: `setIndex+1/totalSets` ("2/5")

**Minimal** (when another activity is also alive and ours collapses to a circle):
- A single filled-fraction ring: `setIndex / totalSets`

**Expanded** (long-press the island):
```
┌─────────────────────────────────────────┐
│  BENCH PRESS                            │  ← title
│  SET 2/5  · staged 140 × ?              │
│  ┌──────┐  ┌──────┐  ┌──────┐           │  ← WorkoutSetButtonRow(.island)
│  │ −1   │  │  =   │  │ +1   │           │
│  └──────┘  └──────┘  └──────┘           │
│  ─────────────────────────────────      │
│  [ End workout ]                        │  ← present only on island; not on lock screen
└─────────────────────────────────────────┘
```

`End workout` button fires a new `EndWorkoutIntent` (added to `WorkoutAppIntents.swift`) that flips `inProgress = false`, calls `WorkoutLiveActivity.endAll(immediate: true)`, and reloads widget timelines.

### "Workout complete" stale state

After the final set's `CommitRepDeltaIntent` flips `state.isComplete = true`:
- Lock-screen view shows: `✓ WORKOUT COMPLETE · X sets · Y min` with no buttons
- Island compact: solid filled dots, no count
- Auto-dismisses 30s later via `dismissalPolicy: .after(...)`

## Open questions resolved with sensible defaults

- **iOS version floor**: 17.0 (already the project floor; interactive LA buttons require 17+).
- **Activity timeout if user abandons mid-workout**: 4 hours since `workoutStartedAt`, then orphan-cleanup ends it on next `bootstrap`.
- **What happens if user starts a 2nd workout while the first's activity is alive?**: `start(state:)` first calls `endAll(immediate: true)` to ensure single-activity invariant. (We also gate `WorkoutSessionView` to single-instance presentation today, so this is defense-in-depth.)
- **Push token / `ActivityKit` push updates**: out of scope. All updates are local via `Activity.update()`. No APNs, no server config.
- **Disabled-LA fallback**: inline banner above Start pill, deep-links to Settings. The widget still works as the fallback surface.
- **Dynamic Island button minimum tap target**: 44×28pt minimum per HIG; `WorkoutSetButtonRow(.island)` enforces.
- **Activity ID stability across `update()`**: ActivityKit handles; we only need to keep the `Activity<>` reference in `WorkoutLiveActivity`'s static cache.

## Migration / first-run

- First launch after install: `Info.plist` declares `NSSupportsLiveActivities`; iOS implicitly grants enable-by-default but user can flip in Settings.
- First workout start: `WorkoutLiveActivity.start` checks `ActivityAuthorizationInfo().areActivitiesEnabled`. If false, sets the App Group flag `liveActivity_disabled_seen` and `WorkoutSessionView` shows the inline banner once. Workout still proceeds — widget is the fallback.
- No backfill / no migration; this is purely additive.

## Tests

No iOS test target exists (per workout-loop v2 convention). Manual smoke matrix:

| Scenario | Expected |
|---|---|
| Start workout, lock phone | Activity visible on lock screen with 3 buttons |
| Tap `+1` on lock screen | Set commits, widget AND activity both refresh, next stage shows |
| Long-press Dynamic Island during workout | Expanded view with End button |
| Tap End on island | Activity dismisses, widget reverts to NextUp |
| Complete final set | "Workout complete" stale state, auto-dismiss 30s |
| Force-quit app mid-workout | Activity persists; tap re-opens app and restores `WorkoutSessionView` |
| Disable Live Activities in Settings | Inline banner appears on next workout start; widget still works |
| Two consecutive workouts | First activity ends cleanly before second starts |

## What's out of scope for v1

- **APNs push updates** for the Live Activity — local-only updates suffice; the user's phone is the source of truth and is open during the workout.
- **Live Activity for non-workout surfaces** (supps reminder, mindful eating window) — separate spec; the workout case is the load-bearing one.
- **Apple Watch complication / mirrored UI** — Watch app doesn't exist in this repo. Future surface.
- **Rest-timer countdown inside the activity** — between-set countdown deferred (same as workout-loop v2 widget out-of-scope item).
- **Customizable activity layout** — single fixed design.
- **Charts / sparklines inside the island** — keeps payload small (4KB cap).
- **Multiple simultaneous activities** — single activity invariant enforced.

## Self-review

- Reuses 100% of the workout-loop v2 state machine and `WorkoutAppIntents` — no parallel logic to keep in sync. The Live Activity is a *third presentation* of the same state (in-app screen + lock-screen widget + live activity).
- The `WorkoutSetButtonRow` extraction also de-dupes the widget's existing button code; it's a small refactor with a coverage win.
- `WorkoutLiveActivityRefresher` lives in the shared module so the AppIntents (which run in the widget extension's process when fired from a lock-screen tap) can refresh the activity without bouncing through the host app.
- Single-activity invariant + 4h orphan cleanup prevents the "ghost activity" failure mode where a force-quit leaves a phantom session pinned forever.
- iOS 17 floor is already the project's floor — no new compatibility burden.
- The "Live Activities disabled" path degrades gracefully to the existing widget; the user is never blocked from logging.

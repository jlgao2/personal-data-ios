# Workout Loop v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the gamified daily-lock loop (streak + 12 achievements), HealthKit auto-pull for workouts, long-press skip-with-reason, and a two-stage interactive lock-screen widget — all per `docs/superpowers/specs/2026-05-09-workout-loop-v2.md`.

**Architecture:** Per-day state stays in App-Group `UserDefaults` (no Core Data, no schema migrations). Three new "Game" types compute streak + achievement state from existing daily-lock keys. A new shared module `PrefrontalCortexShared/` is included in both the host-app and widget-extension targets via `project.yml` so AppIntents and `LockScreenWorkoutState` work in both. The lock-screen widget is a new kind that morphs into the existing `NextUpWidget` UI when no workout is in progress.

**Tech Stack:** Swift 5.10 / iOS 17+, SwiftUI, WidgetKit, AppIntents, HealthKit (`HKWorkoutType` query), App Group `group.com.jlgao.PrefrontalCortex`. xcodegen for project regeneration. xcodebuild for verification (no iOS test target — manual smoke tests at phase boundaries).

**Spec:** `docs/superpowers/specs/2026-05-09-workout-loop-v2.md`

**Working directory:** `/Users/georgegao/personal-data-ios/`

---

## File structure

### NEW (host app)

| Path | Responsibility |
|---|---|
| `PrefrontalCortex/Game/DailyLock.swift` | Per-day lock state. Wraps existing UserDefaults keys (supps AM/PM, mindful eating) + new workout key. Read-only `isComplete(date:)`, mutator `setWorkoutDone(source:reason:)`. |
| `PrefrontalCortex/Game/StreakState.swift` | Codable `current` / `longest` / `lastCompleteDate`. `refresh()` walks back from today, computes consecutive complete-day run. App Group persistence. |
| `PrefrontalCortex/Game/Achievements.swift` | The 12 achievement definitions. Pure-function condition evaluators. `refresh()` returns newly-unlocked ids. App Group persistence. |
| `PrefrontalCortex/Views/DailyLockChip.swift` | 4-dot Now-tab indicator (workout · AM supps · PM supps · mindful). |
| `PrefrontalCortex/Views/SkipWorkoutButton.swift` | Low-contrast text link with cyan fill on long-press (2.0s). |
| `PrefrontalCortex/Views/SkipReasonSheet.swift` | Modal with the 6 reason chips. |
| `PrefrontalCortex/Views/StreakChip.swift` | Profile-tab chip showing current + longest streak. |
| `PrefrontalCortex/Views/AchievementGrid.swift` | 4×3 grid of achievement icons + per-achievement detail sheet. |
| `PrefrontalCortex/Views/AchievementUnlockToast.swift` | Center overlay toast. |

### NEW (shared — compiled into BOTH host app AND widget extension)

| Path | Responsibility |
|---|---|
| `PrefrontalCortexShared/LockScreenWorkoutState.swift` | Codable struct + `LockScreenWorkoutStore` (load/save in App-Group container at `widget_workout_state.json`). |
| `PrefrontalCortexShared/WorkoutAppIntents.swift` | `StageWeightDeltaIntent`, `CommitRepDeltaIntent`, `BandColorCycleIntent`. |
| `PrefrontalCortexShared/WorkoutProgress.swift` | `completeSet(exerciseKey:setIndex:weight:reps:)` — small wrapper around the per-day workout-state UserDefaults keys that `WorkoutSessionView` already uses. Mirrors what `WorkoutSessionView.markComplete` does. |

### NEW (widget extension)

| Path | Responsibility |
|---|---|
| `PrefrontalCortexWidget/WorkoutLockWidget.swift` | TimelineProvider reads `LockScreenWorkoutState`. View branches on `inProgress` (active → stage-aware buttons; idle → NextUp fallback). |

### MODIFIED

| Path | Change |
|---|---|
| `project.yml` | Add `PrefrontalCortexShared/` to both targets' `sources`. Register the new widget. |
| `PrefrontalCortex/HealthKit/HealthStore.swift` | Add `HKObjectType.workoutType()` to authorize. |
| `PrefrontalCortex/HealthKit/SampleExporter.swift` | Add `fetchTodayWorkouts()`; query `HKWorkoutType` for ≥10 min today; map to session rows. |
| `PrefrontalCortex/AppStore.swift` | On bootstrap + foreground: call `SampleExporter.fetchTodayWorkouts()`, then `StreakState.refresh()`, then `Achievements.refresh()`; surface achievement-unlock toast. |
| `PrefrontalCortex/ContentView.swift` | Insert `DailyLockChip` in `interventionsTab`; insert `StreakChip` + `AchievementGrid` in `profileTab`; add `AchievementUnlockToast` overlay. |
| `PrefrontalCortex/Views/AdaptedSessionView.swift` | Place `SkipWorkoutButton` below the START pill row. |
| `PrefrontalCortex/Views/StackView.swift` | After `toggle(period:)`, call `StreakState.refresh()` + `Achievements.refresh()`. |
| `PrefrontalCortex/Views/MindfulEatingTodayView.swift` | After `toggle()`, same hooks. |
| `PrefrontalCortex/Views/WorkoutSessionView.swift` | On `commitAndDismiss()`, call `DailyLock.setWorkoutDone(source: .manual)`. On `onAppear` and on every set commit, sync to `LockScreenWorkoutStore` + reload widget. |
| `PrefrontalCortex/WidgetSnapshotWriter.swift` | Add `streak_current` + `streak_longest` to the snapshot (optional consumption by other widgets — not required for v1). |
| `PrefrontalCortexWidget/PrefrontalCortexWidgetBundle.swift` | Register `WorkoutLockWidget()`. |

### Build helper

`xcodegen generate` is required after editing `project.yml` or adding files. Build verification command throughout this plan:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/georgegao/personal-data-ios/PrefrontalCortex.xcodeproj \
  -scheme PrefrontalCortex \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: |BUILD" | tail -10
```

---

## Phase 1 — Foundation: DailyLock + StreakState + Achievements

Pure data layer. No UI. Verifies via build success only — these types are exercised once Phase 2 wires them in.

### Task 1: Create `DailyLock`

**Files:**
- Create: `PrefrontalCortex/Game/DailyLock.swift`

- [ ] **Step 1: Create the directory and the file**

```bash
mkdir -p /Users/georgegao/personal-data-ios/PrefrontalCortex/Game
```

Write `PrefrontalCortex/Game/DailyLock.swift`:

```swift
import Foundation

/// Per-day lock state. Wraps the existing UserDefaults keys for supps and
/// mindful eating, plus a new key for the workout slot. The four slots
/// AND-together into `isComplete(date:)`, which is the streak's daily gate.
///
/// All keys live in the App Group default suite so the widget extension
/// reads the same source of truth.
enum DailyLock {

    // MARK: - App Group

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // MARK: - Keys

    private static func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.string(from: date)
    }

    private static func workoutDoneKey(_ date: Date) -> String   { "workout_done_\(dateKey(date))" }
    private static func workoutSourceKey(_ date: Date) -> String { "workout_source_\(dateKey(date))" }
    private static func workoutSkipReasonKey(_ date: Date) -> String { "workout_skip_reason_\(dateKey(date))" }
    private static func amSuppsKey(_ date: Date) -> String       { "stack_period_\(dateKey(date))_morning" }
    private static func pmSuppsKey(_ date: Date) -> String       { "stack_period_\(dateKey(date))_evening" }
    private static func mindfulKey(_ date: Date) -> String       { "mindful_eat_\(dateKey(date))" }

    // MARK: - Source enum

    enum WorkoutSource: String {
        case hk
        case manual
        case skip
        case rest_ack
    }

    // MARK: - Per-slot reads

    static func isWorkoutDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: workoutDoneKey(date))
    }
    static func workoutSource(date: Date = Date()) -> WorkoutSource? {
        defaults.string(forKey: workoutSourceKey(date)).flatMap(WorkoutSource.init)
    }
    static func workoutSkipReason(date: Date = Date()) -> String? {
        defaults.string(forKey: workoutSkipReasonKey(date))
    }
    static func isAMSuppsDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: amSuppsKey(date))
    }
    static func isPMSuppsDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: pmSuppsKey(date))
    }
    static func isMindfulEatingDone(date: Date = Date()) -> Bool {
        defaults.bool(forKey: mindfulKey(date))
    }

    // MARK: - The unified gate

    static func isComplete(date: Date = Date()) -> Bool {
        isWorkoutDone(date: date)
            && isAMSuppsDone(date: date)
            && isPMSuppsDone(date: date)
            && isMindfulEatingDone(date: date)
    }

    // MARK: - Workout-slot mutators

    static func setWorkoutDone(source: WorkoutSource, reason: String? = nil, date: Date = Date()) {
        defaults.set(true,            forKey: workoutDoneKey(date))
        defaults.set(source.rawValue, forKey: workoutSourceKey(date))
        if let reason {
            defaults.set(reason, forKey: workoutSkipReasonKey(date))
        }
    }

    static func clearWorkoutDone(date: Date = Date()) {
        defaults.removeObject(forKey: workoutDoneKey(date))
        defaults.removeObject(forKey: workoutSourceKey(date))
        defaults.removeObject(forKey: workoutSkipReasonKey(date))
    }
}
```

- [ ] **Step 2: Build to confirm compile**

Run the standard build command (top of plan).
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/georgegao/personal-data-ios
git add PrefrontalCortex/Game/DailyLock.swift
git commit -m "Game: DailyLock — per-day lock state wrapper"
```

### Task 2: Create `StreakState`

**Files:**
- Create: `PrefrontalCortex/Game/StreakState.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// Streak counter for consecutive complete days. A "complete day" is
/// `DailyLock.isComplete(date:)` returning true for that date.
///
/// Persistence lives in App Group so the widget can read the current
/// streak number without touching UserDefaults.standard.
struct StreakState: Codable {
    var current: Int
    var longest: Int
    var lastCompleteDate: String?  // YYYY-MM-DD

    static let empty = StreakState(current: 0, longest: 0, lastCompleteDate: nil)

    // MARK: - Persistence

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let key = "streak_state"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> StreakState {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(StreakState.self, from: data) else {
            return .empty
        }
        return s
    }

    static func save(_ s: StreakState) {
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: - Recompute

    /// Walk backwards from today, counting consecutive complete days.
    /// Today doesn't have to be complete yet — if yesterday was complete,
    /// the streak is the run ending yesterday and continues incrementing
    /// when today completes.
    static func refresh(now: Date = Date()) -> StreakState {
        let cal = Calendar.current
        var current = StreakState.load()

        // Start from today. If today is complete, count it; else start from yesterday.
        var cursor = cal.startOfDay(for: now)
        var count = 0

        if DailyLock.isComplete(date: cursor) {
            count += 1
        } else {
            // step back one to start counting from yesterday
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        // Walk back consecutive complete days.
        while DailyLock.isComplete(date: cursor) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        current.current = count
        current.longest = max(current.longest, count)

        // Track the most-recent complete date for "starting over · N days
        // was your last run" messaging.
        if DailyLock.isComplete(date: cal.startOfDay(for: now)) {
            current.lastCompleteDate = formatted(now)
        }

        save(current)
        return current
    }

    private static func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
```

- [ ] **Step 2: Build**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/Game/StreakState.swift
git commit -m "Game: StreakState — consecutive-complete-day counter"
```

### Task 3: Create `Achievements`

**Files:**
- Create: `PrefrontalCortex/Game/Achievements.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// The 12 achievements. Pure-function condition evaluators that take the
/// current streak + recent daily-lock history and return whether each
/// achievement should be unlocked. Newly-firing ones return from `refresh()`
/// so the UI can show a toast.
struct Achievement: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String           // SF Symbol
    let condition: (Context) -> Bool

    struct Context {
        let now: Date
        let streak: StreakState
        /// Last 30 days' DailyLock.isComplete results, indexed by YYYY-MM-DD.
        let history: [String: Bool]
        /// Last 30 days' workout sources, indexed by YYYY-MM-DD.
        let sources: [String: DailyLock.WorkoutSource]
        /// Last 30 days' mindful-eating booleans (own track, not full streak).
        let mindful: [String: Bool]
    }
}

enum Achievements {

    // MARK: - Catalog

    static let all: [Achievement] = [
        // Streak milestones
        Achievement(
            id: "first_step",
            name: "First step",
            description: "Logged your first complete day.",
            icon: "figure.walk",
            condition: { $0.streak.longest >= 1 }
        ),
        Achievement(
            id: "week_of_work",
            name: "Week of work",
            description: "7-day streak.",
            icon: "7.circle",
            condition: { $0.streak.longest >= 7 }
        ),
        Achievement(
            id: "tendril",
            name: "Tendril",
            description: "30-day streak.",
            icon: "leaf",
            condition: { $0.streak.longest >= 30 }
        ),
        Achievement(
            id: "roots",
            name: "Roots",
            description: "90-day streak.",
            icon: "tree",
            condition: { $0.streak.longest >= 90 }
        ),
        Achievement(
            id: "pillar",
            name: "Pillar",
            description: "365-day streak.",
            icon: "building.columns",
            condition: { $0.streak.longest >= 365 }
        ),

        // Volume milestones
        Achievement(
            id: "volume_keeper",
            name: "Volume keeper",
            description: "100 total complete days.",
            icon: "hexagon.fill",
            condition: { $0.history.values.filter { $0 }.count >= 100 }
        ),
        Achievement(
            id: "iron_line",
            name: "Iron line",
            description: "365 total complete days.",
            icon: "medal",
            condition: { $0.history.values.filter { $0 }.count >= 365 }
        ),

        // Behavior signals
        Achievement(
            id: "honest_break",
            name: "Honest break",
            description: "Used skip-with-reason 3+ times in a 30-day window.",
            icon: "hand.raised",
            condition: { ctx in
                ctx.sources.values.filter { $0 == .skip }.count >= 3
            }
        ),
        Achievement(
            id: "bounce_back",
            name: "Bounce-back",
            description: "Restarted a streak within 3 days of breaking it.",
            icon: "arrow.uturn.up",
            condition: { ctx in
                // Look for the pattern: at least one complete day, preceded by
                // ≤3 incomplete days, preceded by another complete day.
                let cal = Calendar.current
                let today = cal.startOfDay(for: ctx.now)
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                for back in 0..<10 {
                    guard let recent = cal.date(byAdding: .day, value: -back, to: today),
                          ctx.history[f.string(from: recent)] == true else { continue }
                    // Found a complete day. Look back 1-3 days for the most-recent
                    // complete day before it.
                    for gap in 1...4 {
                        guard let earlier = cal.date(byAdding: .day, value: -gap, to: recent),
                              ctx.history[f.string(from: earlier)] == true else { continue }
                        // Earlier complete day exists. The gap is `gap - 1` incomplete days.
                        // Bounce-back fires if 1-3 incomplete days separated them.
                        if gap >= 2 && gap <= 4 {
                            return true
                        }
                    }
                }
                return false
            }
        ),
        Achievement(
            id: "quiet_rest",
            name: "Quiet rest",
            description: "4 consecutive Sunday rest days acknowledged.",
            icon: "moon.stars",
            condition: { ctx in
                let cal = Calendar.current
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                var consecutive = 0
                var cursor = cal.startOfDay(for: ctx.now)
                // Walk back, looking at each Sunday.
                for _ in 0..<60 {
                    let weekday = cal.component(.weekday, from: cursor)  // 1=Sun
                    if weekday == 1 {
                        let key = f.string(from: cursor)
                        if ctx.sources[key] == .rest_ack || ctx.sources[key] == .skip
                            && ctx.history[key] == true {
                            consecutive += 1
                            if consecutive >= 4 { return true }
                        } else {
                            consecutive = 0
                        }
                    }
                    guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                    cursor = prev
                }
                return false
            }
        ),
        Achievement(
            id: "mindful_month",
            name: "Mindful month",
            description: "30-day mindful-eating streak.",
            icon: "eye.circle",
            condition: { ctx in
                let cal = Calendar.current
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                var cursor = cal.startOfDay(for: ctx.now)
                var run = 0
                for _ in 0..<60 {
                    let key = f.string(from: cursor)
                    if ctx.mindful[key] == true {
                        run += 1
                        if run >= 30 { return true }
                    } else {
                        run = 0
                    }
                    guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                    cursor = prev
                }
                return false
            }
        ),
        Achievement(
            id: "clean_week",
            name: "Clean week",
            description: "Full Mon-Sun of supps both AM and PM.",
            icon: "checkmark.seal",
            condition: { ctx in
                // Walk back finding any Monday-Sunday window where both
                // AM + PM supps were checked every day.
                let cal = Calendar.current
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                let today = cal.startOfDay(for: ctx.now)
                let defaults = UserDefaults(suiteName: "group.com.jlgao.PrefrontalCortex") ?? .standard
                for back in 0..<60 {
                    guard let cursor = cal.date(byAdding: .day, value: -back, to: today) else { break }
                    if cal.component(.weekday, from: cursor) != 1 { continue } // 1 = Sunday
                    // Check that this Sunday and the preceding 6 days all had AM+PM supps.
                    var allClean = true
                    for offset in 0...6 {
                        guard let day = cal.date(byAdding: .day, value: -offset, to: cursor) else {
                            allClean = false; break
                        }
                        let am = defaults.bool(forKey: "stack_period_\(f.string(from: day))_morning")
                        let pm = defaults.bool(forKey: "stack_period_\(f.string(from: day))_evening")
                        if !am || !pm { allClean = false; break }
                    }
                    if allClean { return true }
                }
                return false
            }
        ),
    ]

    // MARK: - State

    struct State: Codable {
        var unlocked: [String: String] = [:]  // id → unlock-date YYYY-MM-DD
    }

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let key = "achievement_state"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> State {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(State.self, from: data) else {
            return State()
        }
        return s
    }

    static func save(_ s: State) {
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: - Refresh

    /// Re-evaluate every achievement. Returns ids of newly-unlocked ones
    /// (existing unlocks are not re-emitted).
    @discardableResult
    static func refresh(now: Date = Date()) -> [String] {
        let context = buildContext(now: now)
        var state = load()
        var newlyUnlocked: [String] = []
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = f.string(from: now)

        for ach in all where state.unlocked[ach.id] == nil && ach.condition(context) {
            state.unlocked[ach.id] = today
            newlyUnlocked.append(ach.id)
        }
        if !newlyUnlocked.isEmpty {
            save(state)
        }
        return newlyUnlocked
    }

    private static func buildContext(now: Date) -> Achievement.Context {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = cal.startOfDay(for: now)
        var history: [String: Bool] = [:]
        var sources: [String: DailyLock.WorkoutSource] = [:]
        var mindful: [String: Bool] = [:]
        for back in 0..<400 {  // Cap at ~13 months for the "Iron line" check
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { break }
            let key = f.string(from: day)
            history[key] = DailyLock.isComplete(date: day)
            if let src = DailyLock.workoutSource(date: day) {
                sources[key] = src
            }
            mindful[key] = DailyLock.isMindfulEatingDone(date: day)
        }
        return .init(now: now, streak: StreakState.load(),
                     history: history, sources: sources, mindful: mindful)
    }
}
```

- [ ] **Step 2: Build**

Run the standard build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/Game/Achievements.swift
git commit -m "Game: Achievements — 12 definitions + condition evaluators"
```

### Task 4: Wire StreakState + Achievements into existing toggles

**Files:**
- Modify: `PrefrontalCortex/Views/StackView.swift` (the period toggle)
- Modify: `PrefrontalCortex/Views/MindfulEatingTodayView.swift` (the daily check)
- Modify: `PrefrontalCortex/Views/WorkoutSessionView.swift` (the commit handler)

- [ ] **Step 1: Hook into StackView's `toggle(period:)`**

Open `PrefrontalCortex/Views/StackView.swift`. Find the existing `toggle(period:)` method. After the existing `UserDefaults.standard.set(...)` line, add a call:

```swift
    private func toggle(period: Period) {
        switch period {
        case .morning: morningDone.toggle()
                       UserDefaults.standard.set(morningDone, forKey: Self.key(.morning))
        case .evening: eveningDone.toggle()
                       UserDefaults.standard.set(eveningDone, forKey: Self.key(.evening))
        }
        // NEW: refresh streak + achievements after any lock-state change.
        _ = StreakState.refresh()
        _ = Achievements.refresh()
    }
```

ALSO change the persistence target from `UserDefaults.standard` to the App Group default suite, so `DailyLock` (which reads from App Group) sees the same values:

```swift
    private static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "group.com.jlgao.PrefrontalCortex") ?? .standard
    }
    // ... use Self.defaults().set(...) and Self.defaults().bool(forKey:) throughout
```

Update both the `loadState()` and `toggle(period:)` reads/writes to use the new `defaults()` helper.

- [ ] **Step 2: Hook into MindfulEatingTodayView's `toggle()`**

Open `PrefrontalCortex/Views/MindfulEatingTodayView.swift`. Find `toggle()`. Switch its UserDefaults usage to App Group, AND append the streak/achievement refresh:

```swift
    private static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "group.com.jlgao.PrefrontalCortex") ?? .standard
    }

    private func toggle() {
        todayChecked.toggle()
        Self.defaults().set(todayChecked, forKey: Self.todayKey)
        recomputeStreak()
        Task { await syncToLaptop() }
        // NEW
        _ = StreakState.refresh()
        _ = Achievements.refresh()
    }

    private func loadState() {
        todayChecked = Self.defaults().bool(forKey: Self.todayKey)
        recomputeStreak()
    }

    private func recomputeStreak() {
        let cal = Calendar.current
        var count = 0
        for offset in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            if Self.defaults().bool(forKey: Self.keyFor(d)) {
                count += 1
            }
        }
        streakDays = count
    }
```

- [ ] **Step 3: Hook into WorkoutSessionView's `commitAndDismiss()`**

Open `PrefrontalCortex/Views/WorkoutSessionView.swift`. Find `commitAndDismiss()`. After the upload attempt (success OR failure), add:

```swift
        // Mark the workout slot done (manual log path) and refresh streak + achievements.
        DailyLock.setWorkoutDone(source: .manual)
        _ = StreakState.refresh()
        _ = Achievements.refresh()
```

Place this just before the `dismiss()` call (whether the upload succeeded or failed — the fact that the user logged sets is what counts).

- [ ] **Step 4: Build**

Run xcodegen + the build command. Expected: `** BUILD SUCCEEDED **`.

```bash
cd /Users/georgegao/personal-data-ios && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PrefrontalCortex.xcodeproj -scheme PrefrontalCortex \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add PrefrontalCortex/Views/StackView.swift \
        PrefrontalCortex/Views/MindfulEatingTodayView.swift \
        PrefrontalCortex/Views/WorkoutSessionView.swift \
        PrefrontalCortex.xcodeproj/project.pbxproj
git commit -m "Game: wire StreakState + Achievements into existing toggles; move supps/mindful keys to App Group"
```

---

## Phase 2 — Now-tab UI: DailyLockChip + SkipWorkoutButton + SkipReasonSheet

### Task 5: Create `DailyLockChip`

**Files:**
- Create: `PrefrontalCortex/Views/DailyLockChip.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Four-dot Now-tab indicator: workout · AM supps · PM supps · mindful eating.
/// Each dot fills cyan when its slot is complete. A thin progress line behind
/// the dots fills 0→1 with the count of completed slots. If today's complete
/// streak ≥ 7, a small "N days running" caption appears below.
struct DailyLockChip: View {

    @State private var refreshTick: Int = 0   // bumped to force redraw when state changes

    private var workoutDone: Bool { DailyLock.isWorkoutDone() }
    private var amDone:      Bool { DailyLock.isAMSuppsDone() }
    private var pmDone:      Bool { DailyLock.isPMSuppsDone() }
    private var mindfulDone: Bool { DailyLock.isMindfulEatingDone() }
    private var doneCount:   Int  { [workoutDone, amDone, pmDone, mindfulDone].filter { $0 }.count }
    private var streak:      Int  { StreakState.load().current }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                slot(filled: workoutDone, label: "W")
                slot(filled: amDone,      label: "AM")
                slot(filled: pmDone,      label: "PM")
                slot(filled: mindfulDone, label: "M")
                Spacer()
                if streak >= 7 {
                    Text("\(streak)d running")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                }
            }
            // Thin progress strip
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.05)).frame(height: 2)
                    Capsule()
                        .fill(Color.cyan.opacity(0.5))
                        .frame(width: geo.size.width * CGFloat(doneCount) / 4.0, height: 2)
                }
            }
            .frame(height: 2)
        }
        .id(refreshTick)
        .onAppear { refreshTick += 1 }
    }

    private func slot(filled: Bool, label: String) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(filled ? Color.cyan : Color.white.opacity(0.12))
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(filled ? Color.cyan : Color.white.opacity(0.2), lineWidth: 1))
                .symbolEffect(.bounce.up, value: filled)
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(filled ? .cyan : .secondary)
                .tracking(1)
        }
    }
}
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/Views/DailyLockChip.swift
git commit -m "Views: DailyLockChip — 4-dot Now-tab progress indicator"
```

### Task 6: Create `SkipReasonSheet`

**Files:**
- Create: `PrefrontalCortex/Views/SkipReasonSheet.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Modal showing the 6 preset reasons when the user holds-skip on the
/// SkipWorkoutButton. Tap a chip → fires the closure → caller persists +
/// dismisses + refreshes streak/achievements.
struct SkipReasonSheet: View {

    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let reasons: [String] = [
        "Sick", "Traveling", "Busy", "Unmotivated", "Injury", "Scheduled rest",
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Why are you skipping today?")
                    .font(.body.italic())
                    .foregroundStyle(.white)
                Text("Logged for the adaptive engine — patterns matter more than perfect days.")
                    .font(.caption2.italic())
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 10) {
                    ForEach(reasons, id: \.self) { r in
                        Button {
                            onPick(r)
                            dismiss()
                        } label: {
                            Text(r)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.cyan.opacity(0.13),
                                            in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.4)))
                        }
                        .buttonStyle(LivePressStyle())
                    }
                }
                Spacer()
            }
            .padding(20)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Skip today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Tiny manual flow-layout — wraps chips onto multiple rows when they overflow.
/// SwiftUI's HStack doesn't wrap; iOS 16+ has a Layout protocol we can use.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/Views/SkipReasonSheet.swift
git commit -m "Views: SkipReasonSheet — 6 reason chips in flow-layout"
```

### Task 7: Create `SkipWorkoutButton`

**Files:**
- Create: `PrefrontalCortex/Views/SkipWorkoutButton.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Low-contrast text link below the Start pill. Long-press 2.0 s to commit;
/// the link visually fills with cyan from left to right as you hold. Release
/// before completion cancels (with a soft spring-back). On completion, the
/// SkipReasonSheet appears.
///
/// Implementation note: SwiftUI's LongPressGesture doesn't expose
/// progress, so we model the fill manually using a DragGesture that starts
/// the timer onChanged and a Timer-driven progress increment until either
/// the gesture ends (cancel) or progress reaches 1 (commit).
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
                // Reset progress after a brief pause so it visually "discharges."
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
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/Views/SkipWorkoutButton.swift
git commit -m "Views: SkipWorkoutButton — 2s long-press fill + reason sheet"
```

### Task 8: Wire `SkipWorkoutButton` into `AdaptedSessionView`

**Files:**
- Modify: `PrefrontalCortex/Views/AdaptedSessionView.swift`

- [ ] **Step 1: Add SkipWorkoutButton below the Start pill**

Open `AdaptedSessionView.swift`. Find the `HStack` containing the START pill (currently inside the section header). Below it, add the skip button.

Locate the existing block that ends with the `if let onStart` button. After that closing `}`, the body continues with traffic-light card. Insert the SkipWorkoutButton AFTER the existing header HStack but BEFORE the "Traffic light header card" `VStack`:

```swift
            }   // end of header HStack with START pill

            // NEW — the skip-with-friction surface, low-key under the Start pill.
            SkipWorkoutButton()
                .padding(.top, -2)

            // Traffic light header card
            VStack(alignment: .leading, spacing: 8) {
                ...
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/Views/AdaptedSessionView.swift
git commit -m "AdaptedSessionView: add SkipWorkoutButton under START pill"
```

### Task 9: Wire `DailyLockChip` into Now tab

**Files:**
- Modify: `PrefrontalCortex/ContentView.swift`

- [ ] **Step 1: Insert DailyLockChip in interventionsTab**

Open `ContentView.swift`. Find `interventionsTab`. Inside the `if let bundle = store.bundle {` block, immediately after `TimelineView(...)` and BEFORE `if let supps = ...`, add:

```swift
                        TimelineView(bundle: bundle, calStore: calStore)
                        DailyLockChip()           // ← NEW
                        if let supps = bundle.profile?.supplement_stack, !supps.isEmpty {
                            StackView(items: supps)
                        }
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/ContentView.swift
git commit -m "ContentView: insert DailyLockChip in Now tab"
```

---

## Phase 3 — Profile UI: StreakChip + AchievementGrid + AchievementUnlockToast

### Task 10: Create `StreakChip`

**Files:**
- Create: `PrefrontalCortex/Views/StreakChip.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Big chip on the Profile tab. Shows current streak + longest-ever +
/// (if streak == 0 and we have history) the "starting over · N days
/// was your last run" nudge.
struct StreakChip: View {

    @State private var refreshTick: Int = 0
    private var state: StreakState { StreakState.load() }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.cyan.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "flame")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                    .symbolEffect(.bounce, value: state.current)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.current) day streak")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                if state.current == 0, let last = state.lastCompleteDate, state.longest > 0 {
                    Text("starting over · \(state.longest) days was your last run")
                        .font(.caption2.italic())
                        .foregroundStyle(.secondary)
                } else {
                    Text("best: \(state.longest)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.18)))
        .id(refreshTick)
        .onAppear { refreshTick += 1 }
    }
}
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/Views/StreakChip.swift
git commit -m "Views: StreakChip — Profile-tab streak chip"
```

### Task 11: Create `AchievementGrid` (with detail sheet)

**Files:**
- Create: `PrefrontalCortex/Views/AchievementGrid.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// 4-column grid of achievement icons. Locked = grey + outlined; unlocked =
/// cyan + filled. Tap any cell → small detail sheet with name, description,
/// and unlock date if applicable.
struct AchievementGrid: View {

    @State private var selected: Achievement? = nil
    private var state: Achievements.State { Achievements.load() }

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACHIEVEMENTS")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
                    .tracking(2)
                Spacer()
                Text("\(state.unlocked.count)/\(Achievements.all.count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Achievements.all) { ach in
                    let unlocked = state.unlocked[ach.id] != nil
                    Button { selected = ach } label: {
                        VStack(spacing: 4) {
                            Image(systemName: ach.icon)
                                .font(.title3)
                                .foregroundStyle(unlocked ? .cyan : .white.opacity(0.25))
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(unlocked ? Color.cyan.opacity(0.15)
                                                       : Color.white.opacity(0.03))
                                )
                                .overlay(Circle().strokeBorder(
                                    unlocked ? Color.cyan.opacity(0.4)
                                             : Color.white.opacity(0.10), lineWidth: 1))
                        }
                    }
                    .buttonStyle(LivePressStyle())
                }
            }
        }
        .sheet(item: $selected) { ach in
            AchievementDetailSheet(achievement: ach,
                                   unlockDate: state.unlocked[ach.id])
                .presentationDetents([.medium])
        }
    }
}

private struct AchievementDetailSheet: View {
    let achievement: Achievement
    let unlockDate: String?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.cyan.opacity(unlockDate != nil ? 0.18 : 0.05))
                    .frame(width: 80, height: 80)
                Image(systemName: achievement.icon)
                    .font(.largeTitle)
                    .foregroundStyle(unlockDate != nil ? .cyan : .white.opacity(0.3))
            }
            Text(achievement.name)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
            Text(achievement.description)
                .font(.body.italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let unlockDate {
                Text("Unlocked \(unlockDate)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan)
            } else {
                Text("locked")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(2)
            }
            Spacer()
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

extension Achievement: Identifiable {}
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/Views/AchievementGrid.swift
git commit -m "Views: AchievementGrid — 4×3 grid + detail sheet"
```

### Task 12: Create `AchievementUnlockToast`

**Files:**
- Create: `PrefrontalCortex/Views/AchievementUnlockToast.swift`

- [ ] **Step 1: Write the file**

```swift
import SwiftUI

/// Center-screen toast shown when one or more achievements unlock.
/// Iterates through new unlocks one at a time, ~2 s each, with a soft bounce.
struct AchievementUnlockToast: View {

    @Binding var pending: [Achievement]   // queue of newly-unlocked
    @State private var visible: Achievement? = nil

    var body: some View {
        ZStack {
            if let ach = visible {
                VStack(spacing: 8) {
                    Image(systemName: ach.icon)
                        .font(.largeTitle)
                        .foregroundStyle(.cyan)
                        .symbolEffect(.bounce, value: ach.id)
                    Text(ach.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                    Text("ACHIEVEMENT UNLOCKED")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                        .tracking(2)
                }
                .padding(20)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.cyan.opacity(0.3)))
                .shadow(color: Color.cyan.opacity(0.25), radius: 18)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .onTapGesture { visible = nil }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: visible?.id)
        .task(id: pending.count) {
            await drainQueue()
        }
    }

    private func drainQueue() async {
        while !pending.isEmpty {
            let next = pending.removeFirst()
            withAnimation { visible = next }
            try? await Task.sleep(for: .seconds(2.0))
            withAnimation { visible = nil }
            try? await Task.sleep(for: .milliseconds(250))  // brief gap between toasts
        }
    }
}
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/Views/AchievementUnlockToast.swift
git commit -m "Views: AchievementUnlockToast — center overlay queue"
```

### Task 13: Wire StreakChip + AchievementGrid + Toast into Profile + ContentView

**Files:**
- Modify: `PrefrontalCortex/ContentView.swift`
- Modify: `PrefrontalCortex/AppStore.swift`

- [ ] **Step 1: Add `pendingAchievements` to AppStore**

Open `AppStore.swift`. Add a new `@Published` property:

```swift
@Published var pendingAchievements: [Achievement] = []
```

In `bootstrap()` and `refreshOnForeground()`, after the existing flow, evaluate achievements and append any new ones:

```swift
        // Tail of bootstrap() / refreshOnForeground():
        let newlyUnlocked = Achievements.refresh()
        if !newlyUnlocked.isEmpty {
            let achs = newlyUnlocked.compactMap { id in
                Achievements.all.first(where: { $0.id == id })
            }
            pendingAchievements.append(contentsOf: achs)
        }
        _ = StreakState.refresh()
```

- [ ] **Step 2: Wire StreakChip + AchievementGrid into profileTab**

Open `ContentView.swift`. Find `profileTab`. At the top of the inner `if let bundle = store.bundle {` block, insert:

```swift
                    if let bundle = store.bundle {
                        StreakChip()                  // ← NEW
                        AchievementGrid()             // ← NEW
                        if let p = bundle.profile {
                            HealthProfileView(profile: p)
                        }
                        ...
```

- [ ] **Step 3: Wire AchievementUnlockToast into TabView body**

In `ContentView`'s top-level `body`, add an overlay below the existing `lastUploadResult` one:

```swift
        .overlay(alignment: .center) {
            AchievementUnlockToast(pending: $store.pendingAchievements)
        }
```

- [ ] **Step 4: Build**

Standard build command. Expected: success.

- [ ] **Step 5: Commit**

```bash
git add PrefrontalCortex/ContentView.swift PrefrontalCortex/AppStore.swift
git commit -m "ContentView: wire StreakChip + AchievementGrid in Profile; toast overlay at root"
```

---

## Phase 4 — HealthKit auto-pull

### Task 14: Authorize HKWorkoutType in HealthStore

**Files:**
- Modify: `PrefrontalCortex/HealthKit/HealthStore.swift`

- [ ] **Step 1: Read the existing `authorize()`**

Open `HealthKit/HealthStore.swift`. Find the existing `authorize()` method. It probably constructs a Set of `HKObjectType` values. Add `HKObjectType.workoutType()` to that set.

```swift
    func authorize() async throws {
        let readTypes: Set<HKObjectType> = [
            // ... existing entries (HK quantity types for HR, RHR, sleep, etc.)
            HKObjectType.workoutType(),                       // ← NEW
        ]
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/HealthKit/HealthStore.swift
git commit -m "HealthStore: request HKWorkoutType read access"
```

### Task 15: Add `fetchTodayWorkouts()` to SampleExporter

**Files:**
- Modify: `PrefrontalCortex/HealthKit/SampleExporter.swift`

- [ ] **Step 1: Add the helper to the existing struct**

Open `SampleExporter.swift`. After the existing `dailySamples()` method, append:

```swift
    /// Pull today's HKWorkout entries (≥10 min) and return them as session
    /// rows ready for /v1/sessions. Each row gets a deterministic
    /// client_id so re-pulls dedupe at the laptop side.
    static func fetchTodayWorkouts() async -> [[String: Any]] {
        let store = HealthStore.shared.store
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }

        let f = ISO8601DateFormatter()
        let dateF = DateFormatter(); dateF.dateFormat = "yyyy-MM-dd"
        dateF.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = dateF.string(from: start)

        return workouts.compactMap { w -> [String: Any]? in
            guard w.duration >= 600 else { return nil }   // 10 min threshold
            let sport = mapWorkoutType(w.workoutActivityType)
            return [
                "client_id":    "hk-\(dateStr)-\(sport)",
                "ts":           f.string(from: w.startDate),
                "sport":        sport,
                "duration_min": Int((w.duration / 60).rounded()),
                "rpe":          NSNull(),
                "note":         "auto-logged from HealthKit",
            ]
        }
    }

    /// Map HKWorkoutActivityType to a canonical uppercase sport string
    /// matching what WorkoutSessionView's Sport enum uses.
    private static func mapWorkoutType(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running, .crossCountrySkiing:   return "RUNNING"
        case .cycling:                        return "CYCLING"
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:     return "STRENGTH_TRAINING"
        case .yoga:                           return "YOGA"
        case .swimming:                       return "SWIMMING"
        case .hiking:                         return "HIKING"
        case .walking:                        return "WALKING"
        case .downhillSkiing:                 return "ALPINE_SKIING"
        default:                              return "OTHER"
        }
    }
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/HealthKit/SampleExporter.swift
git commit -m "SampleExporter: fetchTodayWorkouts — HKWorkoutType ≥10 min → session rows"
```

### Task 16: Wire HK auto-pull into AppStore.bootstrap and refreshOnForeground

**Files:**
- Modify: `PrefrontalCortex/AppStore.swift`

- [ ] **Step 1: Add an HK-pull helper that POSTs + marks the workout slot done**

Open `AppStore.swift`. Add a new private method:

```swift
    /// Fetch today's HKWorkout entries, POST any new ones to /v1/sessions,
    /// and mark the daily-lock workout slot done if at least one ≥10 min
    /// workout exists today.
    private func pullHealthKitWorkouts() async {
        let rows = await SampleExporter.fetchTodayWorkouts()
        guard !rows.isEmpty else { return }

        // POST silently — best-effort, don't fail the bootstrap.
        if await TransportSettings.shared.isConfigured {
            _ = try? await TransportClient.shared.uploadSessions(rows)
        }

        // Mark workout slot done (HK source). Idempotent — safe to call again.
        if !DailyLock.isWorkoutDone() {
            DailyLock.setWorkoutDone(source: .hk)
        }
    }
```

- [ ] **Step 2: Call it from `bootstrap()` and `refreshOnForeground()`**

In `bootstrap()`, after the existing HK-related calls (e.g., after the bundle load), call:

```swift
        await pullHealthKitWorkouts()
```

In `refreshOnForeground()`, similarly add the call after the existing flow:

```swift
        await pullHealthKitWorkouts()
```

Both should be followed by the achievement evaluation that Task 13 added.

- [ ] **Step 3: Build**

Standard build command. Expected: success.

- [ ] **Step 4: Commit**

```bash
git add PrefrontalCortex/AppStore.swift
git commit -m "AppStore: pull HKWorkouts on bootstrap + foreground; mark workout slot via DailyLock"
```

---

## Phase 5 — Lock-screen widget

### Task 17: Create the shared module directory + add to `project.yml`

**Files:**
- Modify: `project.yml`
- Create: `PrefrontalCortexShared/` (empty placeholder)

- [ ] **Step 1: Create the shared directory + a placeholder file**

```bash
mkdir -p /Users/georgegao/personal-data-ios/PrefrontalCortexShared
cat > /Users/georgegao/personal-data-ios/PrefrontalCortexShared/.keep <<'EOF'
This directory is shared between the host app and the widget extension via
project.yml's sources includes. See WorkoutAppIntents.swift, etc.
EOF
```

- [ ] **Step 2: Add the shared sources path to both targets in project.yml**

Open `project.yml`. Find both target blocks (`PrefrontalCortex` and `PrefrontalCortexWidget`). For each, in the `sources:` array, add the shared path:

```yaml
  PrefrontalCortex:
    type: application
    platform: iOS
    sources:
      - path: PrefrontalCortex
        excludes:
          - "**/.DS_Store"
      - path: PrefrontalCortexShared           # ← NEW
        excludes:
          - "**/.keep"
    # ... rest unchanged

  PrefrontalCortexWidget:
    type: app-extension
    platform: iOS
    sources:
      - path: PrefrontalCortexWidget
        excludes:
          - "**/.DS_Store"
      - path: PrefrontalCortexShared           # ← NEW
        excludes:
          - "**/.keep"
    # ... rest unchanged
```

- [ ] **Step 3: Regenerate the Xcode project + build**

```bash
cd /Users/georgegao/personal-data-ios && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PrefrontalCortex.xcodeproj -scheme PrefrontalCortex \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`. Empty shared dir compiles fine.

- [ ] **Step 4: Commit**

```bash
git add project.yml PrefrontalCortex.xcodeproj/ PrefrontalCortexShared/.keep
git commit -m "project: add PrefrontalCortexShared/ to both targets"
```

### Task 18: Create `LockScreenWorkoutState` + `LockScreenWorkoutStore`

**Files:**
- Create: `PrefrontalCortexShared/LockScreenWorkoutState.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// Snapshot of the in-progress workout that both the iOS app and the widget
/// extension can read/write. Persisted as JSON in the App Group container.
struct LockScreenWorkoutState: Codable {
    var inProgress: Bool
    var exerciseKey: String
    var exerciseName: String
    var setIndex: Int
    var totalSets: Int
    var lastWeight: Double
    var lastReps: Int
    var stage: Stage
    var stagedWeight: Double?
    var mode: Mode
    var bandColor: String?
    var unit: String

    enum Stage: String, Codable { case weight, reps }
    enum Mode: String, Codable { case free, band, time, amrap }

    static let idle = LockScreenWorkoutState(
        inProgress: false,
        exerciseKey: "",
        exerciseName: "",
        setIndex: 0,
        totalSets: 0,
        lastWeight: 0,
        lastReps: 0,
        stage: .weight,
        stagedWeight: nil,
        mode: .free,
        bandColor: nil,
        unit: "lb"
    )
}

enum LockScreenWorkoutStore {
    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let filename = "widget_workout_state.json"

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }

    static func load() -> LockScreenWorkoutState {
        guard let url, let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(LockScreenWorkoutState.self, from: data) else {
            return .idle
        }
        return s
    }

    static func save(_ s: LockScreenWorkoutState) {
        guard let url else { return }
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func clear() { save(.idle) }
}
```

- [ ] **Step 2: Build**

Standard build + xcodegen if files were added.

```bash
cd /Users/georgegao/personal-data-ios && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PrefrontalCortex.xcodeproj -scheme PrefrontalCortex \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortexShared/LockScreenWorkoutState.swift PrefrontalCortex.xcodeproj/
git commit -m "Shared: LockScreenWorkoutState — App-Group JSON store for in-progress workout"
```

### Task 19: Create `WorkoutProgress` (shared mutator into per-day storage)

**Files:**
- Create: `PrefrontalCortexShared/WorkoutProgress.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// Mirrors the per-day per-exercise per-set storage that
/// WorkoutSessionView's `markComplete` writes. Used by:
///   - WorkoutSessionView (when user taps a preset in the app)
///   - The lock-screen AppIntents (when user taps a stage button)
///
/// Both paths converge here so the underlying UserDefaults state stays
/// consistent regardless of where the tap came from.
enum WorkoutProgress {

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private static func todayDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private static var stateKey: String { "workout_\(todayDateString())" }

    /// One per-set row matching WorkoutSessionView.SetEntry.
    struct SetEntry: Codable, Equatable {
        var weight: Double
        var reps: Int
        var completed: Bool
        var bandColor: String? = nil
    }

    /// Read all per-exercise set arrays for today.
    static func loadAll() -> [String: [SetEntry]] {
        guard let data = defaults.data(forKey: stateKey),
              let map = try? JSONDecoder().decode([String: [SetEntry]].self, from: data) else {
            return [:]
        }
        return map
    }

    /// Replace the set at (exerciseKey, setIndex) with a completed record,
    /// inheriting the values into the next set if it exists and isn't done.
    /// Persists the per-exercise weight memory for next session.
    static func completeSet(exerciseKey: String, setIndex: Int,
                            weight: Double, reps: Int, bandColor: String? = nil) {
        var all = loadAll()
        guard var arr = all[exerciseKey], setIndex < arr.count else { return }
        arr[setIndex].weight = weight
        arr[setIndex].reps = reps
        arr[setIndex].bandColor = bandColor
        arr[setIndex].completed = true

        // Inherit into next pending set
        let next = setIndex + 1
        if next < arr.count && !arr[next].completed {
            arr[next].weight = weight
            arr[next].reps = reps
            arr[next].bandColor = bandColor
        }
        all[exerciseKey] = arr

        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: stateKey)
        }

        // Memory for next session
        if bandColor != nil {
            defaults.set(bandColor, forKey: "band_\(exerciseKey)")
        } else {
            defaults.set(weight, forKey: "weight_\(exerciseKey)")
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/georgegao/personal-data-ios && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PrefrontalCortex.xcodeproj -scheme PrefrontalCortex \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortexShared/WorkoutProgress.swift PrefrontalCortex.xcodeproj/
git commit -m "Shared: WorkoutProgress — App-Group mutator for per-set state"
```

### Task 20: Create `WorkoutAppIntents`

**Files:**
- Create: `PrefrontalCortexShared/WorkoutAppIntents.swift`

- [ ] **Step 1: Write the file**

```swift
import AppIntents
import WidgetKit

/// Stage 1: pick a weight delta. Updates LockScreenWorkoutState.stagedWeight
/// and advances stage to .reps. Lock-screen widget refreshes to show stage 2.
struct StageWeightDeltaIntent: AppIntent {
    static var title: LocalizedStringResource = "Stage weight delta"
    static var description = IntentDescription("Stage a weight delta for the next set.")

    @Parameter(title: "Delta") var delta: Double

    init() {}
    init(delta: Double) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        guard state.inProgress, state.stage == .weight else { return .result() }
        state.stagedWeight = max(0, state.lastWeight + delta)
        state.stage = .reps
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Stage 2: pick a rep delta. Commits the set via WorkoutProgress, advances
/// to the next set's stage 1, and refreshes the widget.
struct CommitRepDeltaIntent: AppIntent {
    static var title: LocalizedStringResource = "Commit rep delta"
    static var description = IntentDescription("Log this set with the given rep delta and advance.")

    @Parameter(title: "Rep delta") var delta: Int

    init() {}
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        guard state.inProgress else { return .result() }

        let weight: Double
        let bandColor: String?
        switch state.mode {
        case .free, .amrap:
            weight = state.stagedWeight ?? state.lastWeight
            bandColor = nil
        case .band:
            weight = 0
            bandColor = state.bandColor
        case .time:
            // For time mode, "rep" = seconds; weight = 0; no band.
            weight = 0
            bandColor = nil
        }

        let reps = max(0, state.lastReps + delta)

        WorkoutProgress.completeSet(
            exerciseKey: state.exerciseKey,
            setIndex: state.setIndex,
            weight: weight,
            reps: reps,
            bandColor: bandColor
        )

        // Advance set / exercise pointer
        state.setIndex += 1
        if state.setIndex >= state.totalSets {
            // Last set of this exercise — for v1, end the workout. The user
            // can pull up the in-app tracker to start the next exercise.
            state.inProgress = false
        }
        state.stage = .weight
        state.stagedWeight = nil
        state.lastWeight = weight
        state.lastReps = reps
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// For band exercises, stage 1 cycles through the 5 BandColor cases.
/// `direction = -1` (prev) | 0 (same) | +1 (next).
struct BandColorCycleIntent: AppIntent {
    static var title: LocalizedStringResource = "Cycle band color"

    @Parameter(title: "Direction") var direction: Int

    init() {}
    init(direction: Int) { self.direction = direction }

    private static let cycle: [String] = ["yellow", "red", "green", "blue", "black"]

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        guard state.inProgress, state.mode == .band, state.stage == .weight else {
            return .result()
        }
        let current = state.bandColor ?? "green"
        let idx = Self.cycle.firstIndex(of: current) ?? 2
        let newIdx = max(0, min(Self.cycle.count - 1, idx + direction))
        state.bandColor = Self.cycle[newIdx]
        state.stage = .reps   // advance to rep stage
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/georgegao/personal-data-ios && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PrefrontalCortex.xcodeproj -scheme PrefrontalCortex \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortexShared/WorkoutAppIntents.swift PrefrontalCortex.xcodeproj/
git commit -m "Shared: WorkoutAppIntents — Stage/Commit/BandColor intents"
```

### Task 21: Create `WorkoutLockWidget`

**Files:**
- Create: `PrefrontalCortexWidget/WorkoutLockWidget.swift`

- [ ] **Step 1: Write the file**

```swift
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Provider

struct WorkoutLockProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutLockEntry {
        WorkoutLockEntry(date: .now, state: .idle)
    }
    func getSnapshot(in context: Context, completion: @escaping (WorkoutLockEntry) -> Void) {
        completion(WorkoutLockEntry(date: .now, state: LockScreenWorkoutStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutLockEntry>) -> Void) {
        // Single entry; AppIntents trigger explicit reloads on tap.
        let state = LockScreenWorkoutStore.load()
        let entry = WorkoutLockEntry(date: .now, state: state)
        let next = Date().addingTimeInterval(15 * 60)   // hourly refresh as a floor
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WorkoutLockEntry: TimelineEntry {
    let date: Date
    let state: LockScreenWorkoutState
}

// MARK: - Widget

struct WorkoutLockWidget: Widget {
    let kind = "PrefrontalCortexWorkoutLock"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutLockProvider()) { entry in
            WorkoutLockView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Prefrontal Cortex · Next set")
        .description("Log the next set without unlocking. Falls back to NextUp when no workout is active.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

// MARK: - View

struct WorkoutLockView: View {
    let entry: WorkoutLockEntry

    var body: some View {
        if entry.state.inProgress {
            activeView
        } else {
            // Idle — render the same NextUp content the user already
            // configured. (Reads from WidgetSnapshotIO.)
            idleNextUpView
        }
    }

    @ViewBuilder
    private var activeView: some View {
        let s = entry.state
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SET \(s.setIndex + 1)/\(s.totalSets)")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.cyan)
                    .tracking(1.5)
                Spacer()
                Text(s.exerciseName.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(baselineText(s))
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.7))
            buttonRow(for: s)
        }
        .padding(8)
    }

    @ViewBuilder
    private var idleNextUpView: some View {
        // Fallback — show a thin "no workout" placeholder. The existing
        // NextUpWidget covers the rich next-up UI; this one is an at-a-
        // glance "tap me when you start lifting" hint.
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No workout in progress")
                .font(.caption.italic())
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private func baselineText(_ s: LockScreenWorkoutState) -> String {
        switch s.mode {
        case .free, .amrap:
            let stagedDisplay = s.stage == .reps && s.stagedWeight != nil
                ? "staged \(formatWeight(s.stagedWeight!, unit: s.unit)) × ?"
                : "last \(formatWeight(s.lastWeight, unit: s.unit)) × \(s.lastReps)"
            return stagedDisplay
        case .band:
            let color = s.bandColor ?? "—"
            return "last \(color) × \(s.lastReps)"
        case .time:
            return "last \(s.lastReps) sec"
        }
    }

    private func formatWeight(_ w: Double, unit: String) -> String {
        if w == 0 { return "BW" }
        let trimmed = w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))" : String(format: "%g", w)
        return "\(trimmed) \(unit)"
    }

    @ViewBuilder
    private func buttonRow(for s: LockScreenWorkoutState) -> some View {
        switch (s.mode, s.stage) {
        case (.time, _):
            // Single-stage: 3 duration buttons commit directly.
            HStack(spacing: 6) {
                lockButton("−5s",  intent: CommitRepDeltaIntent(delta: -5),  color: .orange)
                lockButton("=",    intent: CommitRepDeltaIntent(delta: 0),   color: .white)
                lockButton("+5s",  intent: CommitRepDeltaIntent(delta: 5),   color: .green)
            }
        case (.amrap, _):
            // Single-stage rep buttons.
            HStack(spacing: 6) {
                lockButton("−1",  intent: CommitRepDeltaIntent(delta: -1),  color: .orange)
                lockButton("=",   intent: CommitRepDeltaIntent(delta: 0),   color: .white)
                lockButton("+1",  intent: CommitRepDeltaIntent(delta: 1),   color: .green)
            }
        case (.band, .weight):
            HStack(spacing: 6) {
                lockButton("←",  intent: BandColorCycleIntent(direction: -1), color: .orange)
                lockButton("=",  intent: BandColorCycleIntent(direction: 0),  color: .white)
                lockButton("→",  intent: BandColorCycleIntent(direction: 1),  color: .green)
            }
        case (.band, .reps), (.free, .reps):
            HStack(spacing: 6) {
                lockButton("−1",  intent: CommitRepDeltaIntent(delta: -1), color: .orange)
                lockButton("=",   intent: CommitRepDeltaIntent(delta: 0),  color: .white)
                lockButton("+1",  intent: CommitRepDeltaIntent(delta: 1),  color: .green)
            }
        case (.free, .weight):
            HStack(spacing: 6) {
                lockButton("−5",  intent: StageWeightDeltaIntent(delta: -5), color: .orange)
                lockButton("=",   intent: StageWeightDeltaIntent(delta: 0),  color: .white)
                lockButton("+5",  intent: StageWeightDeltaIntent(delta: 5),  color: .green)
            }
        }
    }

    private func lockButton<I: AppIntent>(_ label: String, intent: I, color: Color) -> some View {
        Button(intent: intent) {
            Text(label)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(color.opacity(0.15), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/georgegao/personal-data-ios && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PrefrontalCortex.xcodeproj -scheme PrefrontalCortex \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | tail -10
```

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortexWidget/WorkoutLockWidget.swift PrefrontalCortex.xcodeproj/
git commit -m "Widget: WorkoutLockWidget — two-stage lock-screen interactive controls"
```

### Task 22: Register `WorkoutLockWidget` in the bundle

**Files:**
- Modify: `PrefrontalCortexWidget/PrefrontalCortexWidgetBundle.swift`

- [ ] **Step 1: Append the new widget**

Open `PrefrontalCortexWidgetBundle.swift`. Add the new widget to the `var body`:

```swift
@main
struct PrefrontalCortexWidgetBundle: WidgetBundle {
    var body: some Widget {
        HeroWidget()
        SessionWidget()
        ReachOutWidget()
        NextUpWidget()
        WorkoutLockWidget()      // ← NEW
    }
}
```

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortexWidget/PrefrontalCortexWidgetBundle.swift
git commit -m "Widget: register WorkoutLockWidget in bundle"
```

### Task 23: Wire `WorkoutSessionView` to mirror state into `LockScreenWorkoutStore`

**Files:**
- Modify: `PrefrontalCortex/Views/WorkoutSessionView.swift`

- [ ] **Step 1: Add a sync helper**

Open `WorkoutSessionView.swift`. Add a private method:

```swift
    /// Mirror current workout state into the App-Group store the lock-screen
    /// widget reads. Called on focus changes and after every set commit so
    /// the widget always shows the next-set prompt that matches the in-app
    /// active editor.
    private func syncToLockScreen() {
        guard let focused else {
            LockScreenWorkoutStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let entries = sets[focused.exerciseKey] ?? []
        // Find the parsed exercise (we have to re-parse the raw string).
        let raw = allPrescribedItems().first { exerciseKey($0) == focused.exerciseKey } ?? ""
        let parsed = parseExercise(raw)

        let mode: LockScreenWorkoutState.Mode = {
            if parsed.isTime { return .time }
            if parsed.isBand { return .band }
            if parsed.isAMRAP { return .amrap }
            return .free
        }()

        let entry = entries[safe: focused.setIndex] ?? .init(weight: 0, reps: 0, completed: false)

        let state = LockScreenWorkoutState(
            inProgress: true,
            exerciseKey: focused.exerciseKey,
            exerciseName: parsed.name,
            setIndex: focused.setIndex,
            totalSets: parsed.sets,
            lastWeight: entry.weight,
            lastReps: entry.reps,
            stage: .weight,
            stagedWeight: nil,
            mode: mode,
            bandColor: entry.bandColor,
            unit: unit.label
        )
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
    }
```

Add a tiny safe-index extension somewhere in the file:

```swift
private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
```

- [ ] **Step 2: Call syncToLockScreen on every relevant state change**

In `loadState()`, at the end (after `focused = ...` is set), add:

```swift
        syncToLockScreen()
```

In `markComplete(key:index:)`, at the end (after the focus advance / nil), add:

```swift
        syncToLockScreen()
```

In `commitAndDismiss()`, immediately before `dismiss()`, add:

```swift
        LockScreenWorkoutStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
```

- [ ] **Step 3: Add `import WidgetKit` at the top of WorkoutSessionView.swift**

```swift
import SwiftUI
import WidgetKit       // ← NEW
```

- [ ] **Step 4: Build**

Standard build command. Expected: success.

- [ ] **Step 5: Commit**

```bash
git add PrefrontalCortex/Views/WorkoutSessionView.swift
git commit -m "WorkoutSessionView: mirror in-progress state into LockScreenWorkoutStore"
```

---

## Phase 6 — Streak in widget snapshot + manual test plan + final spec sweep

### Task 24: Add streak fields to `WidgetSnapshotShape` and `WidgetSnapshot`

**Files:**
- Modify: `PrefrontalCortex/WidgetSnapshotWriter.swift`
- Modify: `PrefrontalCortexWidget/WidgetSnapshot.swift`

- [ ] **Step 1: Add fields to both copies (they must match)**

In `PrefrontalCortex/WidgetSnapshotWriter.swift`, add to `WidgetSnapshotShape`:

```swift
struct WidgetSnapshotShape: Codable {
    // ... existing fields
    let next_up: [WidgetNextUpItem]?
    let streak_current: Int?              // ← NEW
    let streak_longest: Int?              // ← NEW
}
```

In `derive(...)`, populate them:

```swift
        let streak = StreakState.load()
        return WidgetSnapshotShape(
            // ... existing
            next_up: computeNextUp(bundle: bundle),
            streak_current: streak.current,
            streak_longest: streak.longest
        )
```

In `PrefrontalCortexWidget/WidgetSnapshot.swift`, mirror:

```swift
struct WidgetSnapshot: Codable {
    // ... existing fields
    let next_up: [NextUpItem]?
    let streak_current: Int?              // ← NEW
    let streak_longest: Int?              // ← NEW
}
```

Update the demo data in `HeroWidget.swift` to include `streak_current: nil, streak_longest: nil` so it still constructs.

- [ ] **Step 2: Build**

Standard build command. Expected: success.

- [ ] **Step 3: Commit**

```bash
git add PrefrontalCortex/WidgetSnapshotWriter.swift \
        PrefrontalCortexWidget/WidgetSnapshot.swift \
        PrefrontalCortexWidget/HeroWidget.swift
git commit -m "WidgetSnapshot: add streak_current / streak_longest fields"
```

### Task 25: Final integration build + manual test plan

**Files:** none — verification only.

- [ ] **Step 1: Full clean build**

```bash
cd /Users/georgegao/personal-data-ios && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PrefrontalCortex.xcodeproj -scheme PrefrontalCortex \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO clean build 2>&1 | grep -E "error:|warning: |BUILD" | tail -15
```

Expected: `** BUILD SUCCEEDED **`. Warnings about App-Intents-related schema cache being missing on first build are normal and expected.

- [ ] **Step 2: Smoke-test on simulator (or device)**

Manual checklist for the user to run through in Xcode after pulling the build:

1. **DailyLockChip**: Open Now tab. See 4 dim dots labeled W / AM / PM / M. No streak caption (streak < 7).
2. **Stack**: Tap MORNING button. AM dot fills cyan. Streak caption still hidden.
3. **Stack**: Tap EVENING button. PM dot fills.
4. **Mindful eating**: Tap the mindful-eating button. M dot fills. Now 3 of 4 dots filled.
5. **Adapted Session**: Find the START → pill on the day's session card. Below it, a small "hold to skip today" capsule appears.
6. **Skip flow**: Long-press the skip capsule for 2.0 s — watch the cyan fill animate left to right. Release before completion → springs back. Hold to completion → SkipReasonSheet appears.
7. **Skip commit**: Tap "Sick" → sheet dismisses → W dot fills. All 4 dots now filled.
8. **Streak**: Pull the app to background and re-foreground. Profile tab → StreakChip should show "1 day streak". AchievementGrid → "First step" should be filled.
9. **Profile**: Tap the "First step" cell → detail sheet with description + unlock date.
10. **Workout Session**: Tap START → on the day's session. Pick an exercise's first set → tap "+5 lb" preset. Should advance to set 2. Then tap "Done" → AppStore.lastUploadResult flashes a confirmation.
11. **HealthKit auto-pull**: From a phone with Apple Watch, do a 12+ minute workout. Re-foreground the app. The W dot should auto-fill (HK source).
12. **Lock-screen widget**: Long-press lock screen → Customize → Add Widgets → search "Prefrontal Cortex · Next set" → add to lock-screen rectangle.
    - With a workout in progress (start one in-app first), the widget shows SET N/M + last weight + −5/=/+5 weight buttons.
    - Tap "+5" → widget refreshes to show −1/=/+1 rep buttons. Tap "=" → widget refreshes to next set's stage 1.
    - With no workout in progress, the widget shows "No workout in progress" with a figure.run icon.

- [ ] **Step 3: Commit (no code change — marker commit if you want a clean sequence point)**

Skip if no changes; otherwise:

```bash
git commit --allow-empty -m "Workout Loop v2: implementation complete; manual test plan in plan doc"
```

---

## Self-review

- **Spec coverage:** Every "NEW" file in the spec's File-structure section maps to a task. Every "MODIFIED" file maps to a task. The lock-screen section is realized in Tasks 17–23 (shared module, state, intents, widget, registration, sync). The achievement catalog is fully populated in Task 3 (12 entries with conditions). The skip flow is Tasks 6–8 (sheet, button, AdaptedSession wiring). The HK auto-pull is Tasks 14–16 (auth, fetcher, AppStore wiring). DailyLockChip + StreakChip + AchievementGrid + Toast cover the UI surfaces. ✓
- **Placeholder scan:** No `TBD` / `implement later` / `TODO` / `Add appropriate error handling`. Every code step shows the actual code. The HK type mapping returns `"OTHER"` for un-mapped types as a defensible default rather than throwing. ✓
- **Type consistency:** `DailyLock.WorkoutSource` enum cases (`hk`, `manual`, `skip`, `rest_ack`) are referenced consistently in Tasks 1, 8, 16. `LockScreenWorkoutState.Stage` (`weight`, `reps`) and `Mode` (`free`, `band`, `time`, `amrap`) are stable across Tasks 18, 20, 21, 23. The shared `WorkoutProgress.SetEntry` matches the in-app `WorkoutSessionView.SetEntry` field-for-field. The `Achievement.Context` struct and its properties (`history`, `sources`, `mindful`) are constructed in `Achievements.buildContext` and consumed in each condition closure. ✓
- **Commit cadence:** 24 commits across 6 phases. Each task ends with a commit. Each commit is independently revertable. ✓

---

## Execution choice

Plan complete and saved to `docs/superpowers/plans/2026-05-09-workout-loop-v2.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Best when individual tasks are big enough to benefit from a clean context per task (this plan's tasks average ~80-200 lines of code each, which is at the upper end for subagent batches).

**2. Inline Execution** — execute tasks in this session using the executing-plans skill, batched with checkpoints for review. Best when there's tight coupling between tasks where context-carryover saves time (this plan has some — e.g., the Phase 5 widget tasks all depend on the shared module being right).

My recommendation for this plan: **Inline Execution**. The lock-screen tasks (17–23) are tightly coupled — the AppIntents reference the state, the widget reads the state, WorkoutSessionView writes the state — and the per-task subagent overhead would slow that down without much quality gain. Plus the iOS build verification step is fast (~30s) so we can checkpoint at every commit anyway.

Which approach?

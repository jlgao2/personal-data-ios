# Workout Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land an ActivityKit-based Live Activity that auto-appears on lock screen + Dynamic Island when a workout starts, mirrors the existing `LockScreenWorkoutState`, reuses the widget's button cluster verbatim, and dismisses itself when the workout ends — per `docs/superpowers/specs/2026-05-09-workout-live-activity.md`.

**Architecture:** A new `WorkoutLiveActivityAttributes` (ActivityAttributes + ContentState) lives in `PrefrontalCortexShared/` so both targets can see it. The widget extension declares an `ActivityConfiguration` with three regions (lock-screen + Dynamic Island compact/minimal/expanded), all rendered through a shared `WorkoutSetButtonRow` extracted from `WorkoutLockWidget`. The host app exposes a `WorkoutLiveActivity` static facade (`start/refresh/end/endAll`) called from `WorkoutSessionView.onAppear` and `commitAndDismiss`. The widget-process AppIntents call a shared `WorkoutLiveActivityRefresher.refresh()` after every `LockScreenWorkoutStore.save` so set-logging from the lock screen flows through without bouncing through the host. A new `EndWorkoutIntent` powers the Dynamic Island expanded "End workout" button. Single-activity invariant + 4h orphan cleanup on bootstrap prevent ghost activities.

**Tech Stack:** Swift 5.10 / iOS 17+, SwiftUI, WidgetKit, ActivityKit, AppIntents, App Group `group.com.jlgao.PrefrontalCortex`. xcodegen for project regeneration. xcodebuild for verification (no iOS test target — manual smoke matrix at the end).

**Spec:** `docs/superpowers/specs/2026-05-09-workout-live-activity.md`

**Working directory:** `/Users/georgegao/Projects/personal-data-ios/`

---

## File structure

### NEW (shared — compiled into BOTH host app AND widget extension)

| Path | Responsibility |
|---|---|
| `PrefrontalCortexShared/WorkoutLiveActivityAttributes.swift` | `ActivityAttributes` + `ContentState` + `ContentState.from(_: LockScreenWorkoutState)` adapter. |
| `PrefrontalCortexShared/WorkoutSetButtonRow.swift` | Shared SwiftUI view for the 3-button row, used by widget AND Live Activity. Layout enum: `.compactLockScreen` / `.island`. |
| `PrefrontalCortexShared/WorkoutLiveActivityRefresher.swift` | `static func refresh()` — walks `Activity<WorkoutLiveActivityAttributes>.activities`, builds new `ContentState` from current `LockScreenWorkoutStore.load()`, calls `.update(...)`. Called from every AppIntent so set-logs from the lock screen refresh the LA in-process. |

### NEW (widget extension — UI declaration)

| Path | Responsibility |
|---|---|
| `PrefrontalCortexWidget/WorkoutLiveActivityView.swift` | The `ActivityConfiguration` declaration. Lock-screen view + `dynamicIsland { ... }` (compact leading + compact trailing + minimal + expanded). All button rendering routes through `WorkoutSetButtonRow`. |

### NEW (host app — lifecycle)

| Path | Responsibility |
|---|---|
| `PrefrontalCortex/LiveActivity/WorkoutLiveActivity.swift` | Static facade `start(state:title:)`, `refresh()`, `end(immediate:)`, `endAll(immediate:)`, `cleanupOrphans()`. Handles `areActivitiesEnabled` gate + sets the App-Group disabled-banner flag. |
| `PrefrontalCortex/Views/LiveActivityDisabledBanner.swift` | Inline banner shown above the Start pill if `areActivitiesEnabled == false` and `liveActivity_banner_dismissed_v1` is false. Tapping deep-links to Settings. |

### MODIFIED

| Path | Change |
|---|---|
| `project.yml` | Link `ActivityKit.framework` to host-app target. (Shared sources are already in both targets via the `PrefrontalCortexShared` path.) |
| `PrefrontalCortex/Resources/Info.plist` | Add `NSSupportsLiveActivities: true`. |
| `PrefrontalCortexShared/WorkoutAppIntents.swift` | After every `LockScreenWorkoutStore.save(state)`, call `await WorkoutLiveActivityRefresher.refresh()`. Add new `EndWorkoutIntent` that flips `inProgress=false`, ends all activities, reloads timelines. |
| `PrefrontalCortexWidget/WorkoutLockWidget.swift` | Refactor: replace inline `buttonRow(for:)` + `lockButton(...)` with shared `WorkoutSetButtonRow(state: s, layout: .compactLockScreen)`. No behavior change. |
| `PrefrontalCortexWidget/PrefrontalCortexWidgetBundle.swift` | Register `WorkoutLiveActivityConfiguration()` alongside the existing widgets. |
| `PrefrontalCortex/Views/WorkoutSessionView.swift` | `syncToLockScreen` (line ~688): after `LockScreenWorkoutStore.save(state)`, also call `WorkoutLiveActivity.start(state: state, title: ...)` (idempotent — start no-ops if an activity already exists with same attrs and just refreshes). The clear sites at lines ~670 and ~832 add `WorkoutLiveActivity.endAll(immediate: true)` after `LockScreenWorkoutStore.clear()`. |
| `PrefrontalCortex/AppStore.swift` | `bootstrap()`: add `WorkoutLiveActivity.cleanupOrphans()` early — ends any activity whose `workoutStartedAt > 4h ago`. Wire `LiveActivityDisabledBanner` visibility via existing AppStore-published flag (no new state needed; banner reads `ActivityAuthorizationInfo` directly). |

### Pipeline

No changes. Live Activity is presentation-only; sets still flow through the existing `WorkoutProgress.completeSet` path.

### Build helper

`xcodegen generate` is required after editing `project.yml` or adding files. Build verification command throughout this plan:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex.xcodeproj \
  -scheme PrefrontalCortex \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: |BUILD" | tail -10
```

---

## Phase 1 — Shared module: attributes, button row, refresher

Pure data + view extraction. No host-app integration yet. Verifies via build success — these types are exercised in Phase 2.

### Task 1: Create `WorkoutLiveActivityAttributes`

**Files:**
- Create: `PrefrontalCortexShared/WorkoutLiveActivityAttributes.swift`

- [ ] **Step 1: Write the file**

```swift
import ActivityKit
import Foundation

/// ActivityKit attributes for the in-progress workout Live Activity.
///
/// `WorkoutLiveActivityAttributes` carries the *static* properties that
/// don't change for the lifetime of the activity (start time, title).
/// Everything mutable lives in `ContentState`, which mirrors a strict
/// subset of `LockScreenWorkoutState`. ActivityKit caps `ContentState`
/// payloads at 4KB per update, so we keep the surface narrow.
struct WorkoutLiveActivityAttributes: ActivityAttributes {

    /// Wall-clock when the activity (and the workout session) was started.
    /// Used by the orphan-cleanup pass on `AppStore.bootstrap` to end any
    /// activity older than 4 hours.
    let workoutStartedAt: Date

    /// Human label for the day, e.g. "Day 4 · Back/Biceps". Static for the
    /// life of the activity — exercise name lives in `ContentState` because
    /// it changes between sets.
    let workoutTitle: String

    /// Per-update mutable state. Strict subset of `LockScreenWorkoutState`
    /// (everything except `inProgress`, which is implicit while the activity
    /// is alive).
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

        /// Set true on the final-set commit. Drives the "Workout complete"
        /// stale presentation + the 30s auto-dismiss timer.
        var isComplete: Bool

        /// Adapter from the App-Group store. Both the host and widget
        /// processes use this so the activity payload is identical no
        /// matter who triggered the refresh.
        static func from(_ s: LockScreenWorkoutState, isComplete: Bool = false) -> ContentState {
            ContentState(
                exerciseName: s.exerciseName,
                setIndex: s.setIndex,
                totalSets: s.totalSets,
                lastWeight: s.lastWeight,
                lastReps: s.lastReps,
                stage: s.stage.rawValue,
                stagedWeight: s.stagedWeight,
                mode: s.mode.rawValue,
                bandColor: s.bandColor,
                unit: s.unit,
                isComplete: isComplete
            )
        }
    }
}
```

- [ ] **Step 2: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortexShared/WorkoutLiveActivityAttributes.swift
git commit -m "Shared: WorkoutLiveActivityAttributes — ActivityKit attrs + ContentState adapter"
```

### Task 2: Extract `WorkoutSetButtonRow` from the widget

**Files:**
- Create: `PrefrontalCortexShared/WorkoutSetButtonRow.swift`
- Modify: `PrefrontalCortexWidget/WorkoutLockWidget.swift`

- [ ] **Step 1: Create the shared button-row view**

Write `PrefrontalCortexShared/WorkoutSetButtonRow.swift`:

```swift
import SwiftUI
import AppIntents

/// Per-surface layout knob. `compactLockScreen` matches the rectangular
/// widget's tight padding; `island` slightly larger to meet the HIG 44×28
/// minimum tap target inside the Dynamic Island expanded region.
enum WorkoutSetButtonRowLayout {
    case compactLockScreen
    case island

    var verticalPadding: CGFloat {
        switch self {
        case .compactLockScreen: return 4
        case .island:            return 6
        }
    }
    var horizontalSpacing: CGFloat {
        switch self {
        case .compactLockScreen: return 6
        case .island:            return 8
        }
    }
    var font: Font {
        switch self {
        case .compactLockScreen: return .caption.monospaced().weight(.semibold)
        case .island:            return .footnote.monospaced().weight(.semibold)
        }
    }
}

/// Three-button row driven by `LockScreenWorkoutState`. Used by:
///   • `WorkoutLockWidget` (lock-screen rectangular widget)
///   • `WorkoutLiveActivityView` (lock-screen activity surface AND the
///     Dynamic Island expanded region)
///
/// Identical AppIntent wiring on every surface so a tap on the widget,
/// the lock-screen activity, or the island all flow through the same
/// `StageWeightDeltaIntent` / `CommitRepDeltaIntent` / `BandColorCycleIntent`.
struct WorkoutSetButtonRow: View {
    let state: LockScreenWorkoutState
    let layout: WorkoutSetButtonRowLayout

    init(state: LockScreenWorkoutState, layout: WorkoutSetButtonRowLayout = .compactLockScreen) {
        self.state = state
        self.layout = layout
    }

    var body: some View {
        switch (state.mode, state.stage) {
        case (.time, _):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("−5s", intent: CommitRepDeltaIntent(delta: -5), color: .orange)
                lockButton("=",   intent: CommitRepDeltaIntent(delta: 0),  color: .white)
                lockButton("+5s", intent: CommitRepDeltaIntent(delta: 5),  color: .green)
            }
        case (.amrap, _):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("−1", intent: CommitRepDeltaIntent(delta: -1), color: .orange)
                lockButton("=",  intent: CommitRepDeltaIntent(delta: 0),  color: .white)
                lockButton("+1", intent: CommitRepDeltaIntent(delta: 1),  color: .green)
            }
        case (.band, .weight):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("←", intent: BandColorCycleIntent(direction: -1), color: .orange)
                lockButton("=", intent: BandColorCycleIntent(direction: 0),  color: .white)
                lockButton("→", intent: BandColorCycleIntent(direction: 1),  color: .green)
            }
        case (.band, .reps), (.free, .reps):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("−1", intent: CommitRepDeltaIntent(delta: -1), color: .orange)
                lockButton("=",  intent: CommitRepDeltaIntent(delta: 0),  color: .white)
                lockButton("+1", intent: CommitRepDeltaIntent(delta: 1),  color: .green)
            }
        case (.free, .weight):
            HStack(spacing: layout.horizontalSpacing) {
                lockButton("−5", intent: StageWeightDeltaIntent(delta: -5), color: .orange)
                lockButton("=",  intent: StageWeightDeltaIntent(delta: 0),  color: .white)
                lockButton("+5", intent: StageWeightDeltaIntent(delta: 5),  color: .green)
            }
        }
    }

    @ViewBuilder
    private func lockButton<I: AppIntent>(_ label: String, intent: I, color: Color) -> some View {
        Button(intent: intent) {
            Text(label)
                .font(layout.font)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, layout.verticalPadding)
                .background(color.opacity(0.15), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Refactor `WorkoutLockWidget` to call the shared row**

In `PrefrontalCortexWidget/WorkoutLockWidget.swift`, delete the inline `buttonRow(for:)` + `lockButton(...)` helpers (lines ~107–155) and replace the call site inside `activeView`.

```swift
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
        WorkoutSetButtonRow(state: s, layout: .compactLockScreen)
    }
    .padding(8)
}
```

Then delete the now-unused `buttonRow(for:)` and `lockButton(...)` private methods (the SwiftUI helpers that lived at the bottom of the file). Leave `baselineText(_:)` and `formatWeight(_:unit:)` in place — they're widget-only.

- [ ] **Step 3: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortexShared/WorkoutSetButtonRow.swift PrefrontalCortexWidget/WorkoutLockWidget.swift
git commit -m "Shared: WorkoutSetButtonRow extracted from widget; lock widget uses it"
```

### Task 3: Create `WorkoutLiveActivityRefresher`

**Files:**
- Create: `PrefrontalCortexShared/WorkoutLiveActivityRefresher.swift`

- [ ] **Step 1: Write the file**

This lives in the shared module so widget-process AppIntents can call it directly — no host-app dependency needed. ActivityKit's `Activity<>` type works in any process that links ActivityKit, and the widget extension already does (transitively via WidgetKit). This is the "thin wrapper" the spec calls out.

```swift
import ActivityKit
import Foundation

/// Refreshes any in-flight Workout Live Activity from the current
/// `LockScreenWorkoutStore` state. Runs in whichever process called
/// it — host app on session-view changes, widget extension on a
/// lock-screen button tap. Safe to call when no activity is active
/// (it just no-ops).
enum WorkoutLiveActivityRefresher {

    /// Called from `WorkoutAppIntents.perform()` after persisting state.
    /// If the live state has rolled past the final set, end the activity
    /// with a 30-second dismissal grace so the user sees the completion
    /// before it disappears.
    @available(iOS 16.1, *)
    static func refresh() async {
        let state = LockScreenWorkoutStore.load()
        let isComplete = !state.inProgress
        let content = WorkoutLiveActivityAttributes.ContentState.from(state, isComplete: isComplete)

        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            if isComplete {
                await activity.end(
                    ActivityContent(state: content, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(30))
                )
            } else {
                await activity.update(
                    ActivityContent(state: content, staleDate: nil)
                )
            }
        }
    }

    /// Force-end every active workout activity immediately. Used by the
    /// host app on `commitAndDismiss` and by `EndWorkoutIntent`.
    @available(iOS 16.1, *)
    static func endAllImmediate() async {
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            let content = WorkoutLiveActivityAttributes.ContentState.from(
                LockScreenWorkoutStore.load(), isComplete: true
            )
            await activity.end(
                ActivityContent(state: content, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}
```

- [ ] **Step 2: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortexShared/WorkoutLiveActivityRefresher.swift
git commit -m "Shared: WorkoutLiveActivityRefresher — cross-process LA update facade"
```

### Phase 1 verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex.xcodeproj \
  -scheme PrefrontalCortex \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: |BUILD" | tail -10
```

Expected: `** BUILD SUCCEEDED **`. Three new shared files compile into both targets.

---

## Phase 2 — Widget extension: ActivityConfiguration UI

Declares the Live Activity's three regions (lock screen + island compact/minimal/expanded) and registers it in the widget bundle. Still no host-app start/end calls — that's Phase 4.

### Task 1: Create `WorkoutLiveActivityView`

**Files:**
- Create: `PrefrontalCortexWidget/WorkoutLiveActivityView.swift`

- [ ] **Step 1: Write the file**

```swift
import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

/// The Live Activity declaration for the in-progress workout.
///
/// ActivityKit forces this to live in the widget extension (same place
/// `Widget` types live). The host app starts/updates/ends activities by
/// calling into ActivityKit directly (`WorkoutLiveActivity` facade);
/// rendering is entirely done here.
struct WorkoutLiveActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            // Lock-screen / banner presentation
            WorkoutLiveActivityLockScreenView(
                attrs: context.attributes,
                content: context.state
            )
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — long-press to reveal
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.exerciseName.uppercased())
                        .font(.footnote.monospaced().bold())
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("SET \(context.state.setIndex + 1)/\(context.state.totalSets)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(IslandSubtitle.text(content: context.state))
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.7))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isComplete {
                        completeBanner
                    } else {
                        VStack(spacing: 6) {
                            WorkoutSetButtonRow(
                                state: LockScreenWorkoutStore.load(),
                                layout: .island
                            )
                            Divider().background(.white.opacity(0.2))
                            Button(intent: EndWorkoutIntent()) {
                                Text("End workout")
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.red.opacity(0.4)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } compactLeading: {
                IslandDots(setIndex: context.state.setIndex,
                           totalSets: context.state.totalSets)
            } compactTrailing: {
                Text("\(context.state.setIndex + 1)/\(context.state.totalSets)")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.cyan)
            } minimal: {
                IslandRing(setIndex: context.state.setIndex,
                           totalSets: context.state.totalSets)
            }
            .keylineTint(.cyan)
        }
    }

    @ViewBuilder
    private var completeBanner: some View {
        Text("✓ WORKOUT COMPLETE")
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

// MARK: - Lock-screen view

private struct WorkoutLiveActivityLockScreenView: View {
    let attrs: WorkoutLiveActivityAttributes
    let content: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SET \(content.setIndex + 1)/\(content.totalSets)")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.cyan)
                    .tracking(1.5)
                Spacer()
                Text(content.exerciseName.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if content.isComplete {
                Text("✓ WORKOUT COMPLETE")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.top, 6)
            } else {
                Text(IslandSubtitle.text(content: content))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                // The lock-screen surface intentionally OMITS the End
                // button — the spec calls that out as island-only because
                // the lock screen surface is glanceable, not interactive
                // for high-stakes operations.
                WorkoutSetButtonRow(
                    state: LockScreenWorkoutStore.load(),
                    layout: .compactLockScreen
                )
            }
        }
        .padding(8)
    }
}

// MARK: - Subtitle formatter (shared between lock + island)

private enum IslandSubtitle {
    static func text(content: WorkoutLiveActivityAttributes.ContentState) -> String {
        switch content.mode {
        case "free", "amrap":
            if content.stage == "reps", let staged = content.stagedWeight {
                return "staged \(formatWeight(staged, unit: content.unit)) × ?"
            }
            return "last \(formatWeight(content.lastWeight, unit: content.unit)) × \(content.lastReps)"
        case "band":
            let color = content.bandColor ?? "—"
            return "last \(color) × \(content.lastReps)"
        case "time":
            return "last \(content.lastReps) sec"
        default:
            return ""
        }
    }
    private static func formatWeight(_ w: Double, unit: String) -> String {
        if w == 0 { return "BW" }
        let trimmed = w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))" : String(format: "%g", w)
        return "\(trimmed) \(unit)"
    }
}

// MARK: - Compact leading dots

private struct IslandDots: View {
    let setIndex: Int
    let totalSets: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(totalSets, 1), id: \.self) { i in
                Circle()
                    .fill(i < setIndex ? Color.cyan : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.leading, 2)
    }
}

// MARK: - Minimal ring

private struct IslandRing: View {
    let setIndex: Int
    let totalSets: Int
    var body: some View {
        let frac = totalSets > 0 ? Double(setIndex) / Double(totalSets) : 0
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, frac))
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
    }
}
```

- [ ] **Step 2: Build (will fail until Task 2 + Task 3)**

Skip building — `EndWorkoutIntent` doesn't exist yet. Build at end of Phase 2.

- [ ] **Step 3: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortexWidget/WorkoutLiveActivityView.swift
git commit -m "Widget: WorkoutLiveActivityConfiguration — lock + DI compact/minimal/expanded"
```

### Task 2: Add `EndWorkoutIntent` + refresh hooks to `WorkoutAppIntents`

**Files:**
- Modify: `PrefrontalCortexShared/WorkoutAppIntents.swift`

- [ ] **Step 1: Add the End intent and call refresh from every existing intent**

Replace the entire file with:

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
        if #available(iOS 16.1, *) { await WorkoutLiveActivityRefresher.refresh() }
        return .result()
    }
}

/// Stage 2: pick a rep delta. Commits the set via WorkoutProgress, advances
/// to the next set's stage 1, and refreshes the widget + Live Activity.
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

        state.setIndex += 1
        if state.setIndex >= state.totalSets {
            state.inProgress = false
        }
        state.stage = .weight
        state.stagedWeight = nil
        state.lastWeight = weight
        state.lastReps = reps
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 16.1, *) { await WorkoutLiveActivityRefresher.refresh() }
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
        state.stage = .reps
        LockScreenWorkoutStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 16.1, *) { await WorkoutLiveActivityRefresher.refresh() }
        return .result()
    }
}

/// Powers the "End workout" button in the Dynamic Island expanded region.
/// Flips inProgress=false, ends every Live Activity immediately, and
/// reloads widget timelines so the rectangular widget reverts to NextUp.
/// Intentionally NOT exposed on the lock-screen surface (per spec — too
/// easy to fat-finger from a glanceable surface).
struct EndWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "End workout"
    static var description = IntentDescription("End the current workout session.")

    init() {}

    func perform() async throws -> some IntentResult {
        var state = LockScreenWorkoutStore.load()
        state.inProgress = false
        LockScreenWorkoutStore.save(state)
        if #available(iOS 16.1, *) { await WorkoutLiveActivityRefresher.endAllImmediate() }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

- [ ] **Step 2: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortexShared/WorkoutAppIntents.swift
git commit -m "Intents: refresh LA after every save; add EndWorkoutIntent for island"
```

### Task 3: Register the activity in the widget bundle

**Files:**
- Modify: `PrefrontalCortexWidget/PrefrontalCortexWidgetBundle.swift`

- [ ] **Step 1: Add the new configuration**

Replace the file with:

```swift
import WidgetKit
import SwiftUI

@main
struct PrefrontalCortexWidgetBundle: WidgetBundle {
    var body: some Widget {
        HeroWidget()
        SessionWidget()
        ReachOutWidget()
        WorkoutLockWidget()
        if #available(iOS 16.1, *) {
            WorkoutLiveActivityConfiguration()
        }
    }
}
```

- [ ] **Step 2: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortexWidget/PrefrontalCortexWidgetBundle.swift
git commit -m "Widget bundle: register WorkoutLiveActivityConfiguration"
```

### Phase 2 verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex.xcodeproj \
  -scheme PrefrontalCortex \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: |BUILD" | tail -10
```

Expected: `** BUILD SUCCEEDED **`. Both host-app and widget-extension targets compile.

---

## Phase 3 — Project plumbing: ActivityKit + Info.plist + xcodegen

Wire ActivityKit into the host-app target and flip the LA opt-in flag in Info.plist. No code yet — this just makes the next phase's `import ActivityKit` work in host-app code and tells the OS that this app supports Live Activities.

### Task 1: Link ActivityKit + flip the Info.plist switch

**Files:**
- Modify: `project.yml`
- Modify: `PrefrontalCortex/Resources/Info.plist`

- [ ] **Step 1: Add `NSSupportsLiveActivities` to the host Info.plist via project.yml**

Edit `project.yml` — under the `PrefrontalCortex` target's `info.properties`, add `NSSupportsLiveActivities: true`. The full block becomes:

```yaml
    info:
      path: PrefrontalCortex/Resources/Info.plist
      properties:
        CFBundleDisplayName: Prefrontal Cortex
        UILaunchScreen:
          UIColorName: ""
        NSHealthShareUsageDescription: Reads heart rate, sleep, weight, and other vitals to surface daily targets vs your genome and lab profile.
        NSHealthUpdateUsageDescription: Optional — write session annotations back to your health record.
        NSCalendarsFullAccessUsageDescription: Surfaces your upcoming events on the Now tab and lets you create reminders from Goals + Reach Out.
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
        NSLocalNetworkUsageDescription: Connect to your laptop on the same Wi-Fi to sync the daily bundle.
        UIBackgroundModes:
          - fetch
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        NSSupportsLiveActivities: true
```

- [ ] **Step 2: Add explicit ActivityKit framework link to host-app target**

Under the `PrefrontalCortex` target in `project.yml`, add a `dependencies` entry for `ActivityKit.framework` alongside the existing widget dependency. The dependencies block becomes:

```yaml
    dependencies:
      - target: PrefrontalCortexWidget
      - sdk: ActivityKit.framework
```

(WidgetKit pulls ActivityKit transitively into the extension, but the host app uses `Activity.request(...)` directly, so an explicit link is required.)

- [ ] **Step 3: Regenerate the Xcode project**

```bash
cd /Users/georgegao/Projects/personal-data-ios
xcodegen generate
```

Expected: `Generated project successfully`.

- [ ] **Step 4: Confirm the Info.plist value landed**

```bash
/usr/libexec/PlistBuddy -c 'Print :NSSupportsLiveActivities' \
  /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex/Resources/Info.plist
```

Expected: `true`. (xcodegen merges `info.properties` into the actual Info.plist file on disk.)

- [ ] **Step 5: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add project.yml PrefrontalCortex/Resources/Info.plist PrefrontalCortex.xcodeproj
git commit -m "Project: link ActivityKit; NSSupportsLiveActivities=true"
```

### Phase 3 verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex.xcodeproj \
  -scheme PrefrontalCortex \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: |BUILD" | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

---

## Phase 4 — Host-app facade: WorkoutLiveActivity + disabled banner

The host-app entry points: a static facade for `start/refresh/end/endAll/cleanupOrphans` and the inline banner shown when the user has Live Activities disabled.

### Task 1: Create the `WorkoutLiveActivity` facade

**Files:**
- Create: `PrefrontalCortex/LiveActivity/WorkoutLiveActivity.swift`

- [ ] **Step 1: Create the directory + file**

```bash
mkdir -p /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex/LiveActivity
```

Write `PrefrontalCortex/LiveActivity/WorkoutLiveActivity.swift`:

```swift
import ActivityKit
import Foundation
import WidgetKit

/// Static facade for the workout Live Activity, owned by the host app.
///
/// Single-activity invariant: `start(...)` always calls `endAll(immediate:
/// true)` first so a stale activity from a previous session can't shadow
/// the new one. `cleanupOrphans()` runs from `AppStore.bootstrap` and ends
/// any activity whose `workoutStartedAt` is older than 4 hours.
///
/// All updates are local — no APNs / push token required. The widget
/// process drives mid-session updates via `WorkoutLiveActivityRefresher`
/// (in the shared module) so a lock-screen tap doesn't have to round-trip
/// through the host.
@available(iOS 16.2, *)
enum WorkoutLiveActivity {

    private static let appGroup = "group.com.jlgao.PrefrontalCortex"
    private static let bannerSeenKey = "liveActivity_disabled_seen_v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Are Live Activities currently allowed by the user? `false` means
    /// the user toggled them off in Settings → Notifications. We never
    /// hard-fail on this — the rectangular widget remains the fallback
    /// and we surface a one-time inline banner pointing to Settings.
    static var isAuthorized: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start a new activity for the in-progress workout. Idempotent: if
    /// an activity already exists, refresh it in place rather than
    /// requesting a duplicate.
    static func start(state: LockScreenWorkoutState, title: String) {
        guard isAuthorized else {
            // Surface the one-time disabled banner on next render.
            defaults.set(true, forKey: bannerSeenKey)
            return
        }

        // Single-activity invariant — ensure no leftover from a prior
        // session (or a crash mid-session) is still alive.
        if let existing = Activity<WorkoutLiveActivityAttributes>.activities.first {
            // If attrs match (same workoutStartedAt window), update; else end + restart.
            let mins = -existing.attributes.workoutStartedAt.timeIntervalSinceNow / 60
            if mins < 240 {
                Task { await refresh() }
                return
            }
            Task { await endAll(immediate: true) }
        }

        let attrs = WorkoutLiveActivityAttributes(
            workoutStartedAt: Date(),
            workoutTitle: title
        )
        let content = WorkoutLiveActivityAttributes.ContentState.from(state)

        do {
            _ = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: content, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Surfacing this anywhere except logs is overkill — the
            // widget is the fallback and there's no recovery action.
            print("WorkoutLiveActivity.start failed: \(error)")
        }
    }

    /// Update every active workout activity from the current store state.
    static func refresh() async {
        await WorkoutLiveActivityRefresher.refresh()
    }

    /// End every active workout activity. `immediate=true` dismisses
    /// instantly; `false` schedules a 30s grace via `.after(...)` so the
    /// user can read the completion banner.
    static func endAll(immediate: Bool) async {
        if immediate {
            await WorkoutLiveActivityRefresher.endAllImmediate()
            return
        }
        let content = WorkoutLiveActivityAttributes.ContentState.from(
            LockScreenWorkoutStore.load(), isComplete: true
        )
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: content, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30))
            )
        }
    }

    /// Defensive sweep on `AppStore.bootstrap`. If the user force-quit
    /// the app mid-workout and never came back, the activity could still
    /// be alive (ActivityKit lets them live up to 8 hours by default).
    /// 4 hours is the spec's chosen ceiling — past that, anything alive
    /// is almost certainly an orphan.
    static func cleanupOrphans(now: Date = Date()) {
        let cutoff: TimeInterval = 4 * 60 * 60
        Task {
            for activity in Activity<WorkoutLiveActivityAttributes>.activities {
                let age = now.timeIntervalSince(activity.attributes.workoutStartedAt)
                if age > cutoff {
                    let content = WorkoutLiveActivityAttributes.ContentState.from(
                        LockScreenWorkoutStore.load(), isComplete: true
                    )
                    await activity.end(
                        ActivityContent(state: content, staleDate: nil),
                        dismissalPolicy: .immediate
                    )
                }
            }
        }
    }

    /// Banner gate read by `LiveActivityDisabledBanner`.
    static var shouldShowDisabledBanner: Bool {
        guard !isAuthorized else { return false }
        return !defaults.bool(forKey: "liveActivity_banner_dismissed_v1")
    }

    static func dismissDisabledBanner() {
        defaults.set(true, forKey: "liveActivity_banner_dismissed_v1")
    }
}
```

- [ ] **Step 2: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortex/LiveActivity/WorkoutLiveActivity.swift
git commit -m "Host: WorkoutLiveActivity facade — start/refresh/end/cleanupOrphans"
```

### Task 2: Create `LiveActivityDisabledBanner`

**Files:**
- Create: `PrefrontalCortex/Views/LiveActivityDisabledBanner.swift`

- [ ] **Step 1: Write the file**

```swift
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
```

- [ ] **Step 2: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortex/Views/LiveActivityDisabledBanner.swift
git commit -m "Host: LiveActivityDisabledBanner — inline opt-in nudge"
```

### Phase 4 verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex.xcodeproj \
  -scheme PrefrontalCortex \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: |BUILD" | tail -10
```

Expected: `** BUILD SUCCEEDED **`. Host app links ActivityKit cleanly; both new files compile.

---

## Phase 5 — Wire into WorkoutSessionView + AppStore

This is where the activity actually starts/ends in real sessions.

### Task 1: Start the activity from `syncToLockScreen`, end it from the clear paths

**Files:**
- Modify: `PrefrontalCortex/Views/WorkoutSessionView.swift`

- [ ] **Step 1: Add the start call inside `syncToLockScreen`**

Locate `syncToLockScreen()` (around line 668). After `LockScreenWorkoutStore.save(state)` (around line 701), add the LA start. The full method becomes:

```swift
private func syncToLockScreen() {
    guard let focused else {
        LockScreenWorkoutStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 16.2, *) {
            Task { await WorkoutLiveActivity.endAll(immediate: true) }
        }
        return
    }
    let entries = sets[focused.exerciseKey] ?? []
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

    // Live Activity: idempotent — start() refreshes if one already exists,
    // requests a new one otherwise. Title combines the day key with the
    // session label from the prescribed bundle when present.
    if #available(iOS 16.2, *) {
        let title = (prescribed?.session ?? dayKey)
        WorkoutLiveActivity.start(state: state, title: title)
        Task { await WorkoutLiveActivity.refresh() }
    }
}
```

- [ ] **Step 2: Add the end call inside `commitAndDismiss`**

Locate `commitAndDismiss()` (around line 798). Replace the trailing `LockScreenWorkoutStore.clear()` block (around line 832) with:

```swift
        DailyLock.setWorkoutDone(source: .manual)
        _ = StreakState.refresh()
        _ = Achievements.refresh()
        LockScreenWorkoutStore.clear()
        if #available(iOS 16.2, *) {
            await WorkoutLiveActivity.endAll(immediate: true)
        }
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
```

- [ ] **Step 3: Surface the disabled banner above the Start pill**

Find the toolbar / start area near the top of the view body (the same place the `Done` button is anchored, around line 86). Insert the banner just above the existing form / start cluster:

```swift
.safeAreaInset(edge: .top) {
    if #available(iOS 16.2, *) {
        LiveActivityDisabledBanner()
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}
```

(If `WorkoutSessionView` already has a `.safeAreaInset(edge: .top)`, fold the banner into the existing one rather than adding a second.)

- [ ] **Step 4: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortex/Views/WorkoutSessionView.swift
git commit -m "Session: start LA on focus change; end on commitAndDismiss; banner inset"
```

### Task 2: Orphan-cleanup on bootstrap

**Files:**
- Modify: `PrefrontalCortex/AppStore.swift`

- [ ] **Step 1: Call cleanupOrphans early in `bootstrap`**

Locate `func bootstrap() async` (line 70). Insert the cleanup call right after `loading = true`:

```swift
func bootstrap() async {
    loading = true
    if #available(iOS 16.2, *) {
        WorkoutLiveActivity.cleanupOrphans()
    }
    do {
        try await HealthStore.shared.authorize()
    } catch {
        lastError = "HealthKit authorization failed: \(error.localizedDescription)"
    }
    // ... rest unchanged ...
```

- [ ] **Step 2: Build**

Run the standard build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git add PrefrontalCortex/AppStore.swift
git commit -m "AppStore: cleanupOrphans on bootstrap (4h ceiling)"
```

### Phase 5 verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex.xcodeproj \
  -scheme PrefrontalCortex \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: |BUILD" | tail -10
```

Expected: `** BUILD SUCCEEDED **`. Full app links and builds with the activity wired into the session lifecycle.

---

## Phase 6 — Final verification + manual smoke matrix

The build is green, but ActivityKit can only be exercised on a real device or simulator under interactive use. The matrix below is the spec's required acceptance.

### Task 1: Final build with widget scheme

- [ ] **Step 1: Build with the widget scheme to confirm the extension also compiles cleanly**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex.xcodeproj \
  -scheme PrefrontalCortexWidget \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: |BUILD" | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Confirm Info.plist on disk has the LA flag**

```bash
/usr/libexec/PlistBuddy -c 'Print :NSSupportsLiveActivities' \
  /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex/Resources/Info.plist
```

Expected: `true`.

- [ ] **Step 3: Confirm ActivityKit is linked into the host app product**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /Users/georgegao/Projects/personal-data-ios/PrefrontalCortex.xcodeproj \
  -scheme PrefrontalCortex \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -showBuildSettings 2>&1 | grep -E "OTHER_LDFLAGS|FRAMEWORK_SEARCH_PATHS" | head -5
```

Expected: build settings print without error (specific framework linkage is implicit via `dependencies: - sdk: ActivityKit.framework`).

### Task 2: Manual smoke matrix (run on iPhone 14 Pro+ simulator or device)

Spin up the simulator, install, and run through every row. Check off only after observed behavior matches.

| # | Scenario | Expected | Observed |
|---|---|---|---|
| 1 | Cold-launch app, open Now tab | No activity exists, no banner unless LA disabled | - [ ] |
| 2 | Tap Start workout, swipe to lock screen | Live Activity visible: `SET 1/N · EXERCISE`, baseline line, 3 buttons | - [ ] |
| 3 | On lock screen tap `+5` | `staged 145 × ?` line appears; activity refreshes in place; widget refreshes too | - [ ] |
| 4 | On lock screen tap `+1` | Set commits; next set's stage 1 (weight) shows; both surfaces in sync | - [ ] |
| 5 | Long-press Dynamic Island during workout | Expanded view shows exercise + SET x/N + 3 buttons + red "End workout" | - [ ] |
| 6 | Tap `End workout` on island | Activity dismisses immediately; widget reverts to NextUp; in-app session ends | - [ ] |
| 7 | Run a workout to the final-set commit | Lock-screen activity flips to "✓ WORKOUT COMPLETE"; auto-dismisses ~30s later | - [ ] |
| 8 | Force-quit app mid-workout, wait 5s, reopen | Activity persists across the kill; opening the app restores `WorkoutSessionView` and the activity continues to refresh | - [ ] |
| 9 | Settings → Notifications → Allow Live Activities OFF; start workout | Inline orange banner shown above Start pill; tapping deep-links to Settings; widget still works as fallback | - [ ] |
| 10 | Tap `X` on the disabled banner | Banner dismisses; flag persists across launches; banner does not return until reinstall | - [ ] |
| 11 | Start workout A, dismiss session, start workout B | Activity from A ends cleanly before B's activity starts (single-activity invariant) | - [ ] |
| 12 | Manually set device clock 5h ahead, relaunch app | `cleanupOrphans` ends the stale activity from before the clock jump; widget reverts to idle | - [ ] |
| 13 | Compact island during workout | Leading shows N dots filled to current set; trailing shows `2/5` | - [ ] |
| 14 | Two-activity scenario (alarm + workout) → minimal | Minimal ring shows fraction of sets complete | - [ ] |
| 15 | Band exercise active set | Lock screen shows `last green × 12`; arrows cycle band color via `BandColorCycleIntent` | - [ ] |

- [ ] **Step 3: Once all 15 rows pass, commit a marker**

```bash
cd /Users/georgegao/Projects/personal-data-ios
git commit --allow-empty -m "LA smoke matrix passed (15/15)"
```

---

## Done

The Workout Live Activity is now:

- declared in `PrefrontalCortexShared/WorkoutLiveActivityAttributes.swift` and rendered by `PrefrontalCortexWidget/WorkoutLiveActivityView.swift`
- driven by the same `LockScreenWorkoutState` + `WorkoutAppIntents` the rectangular widget uses (zero state duplication)
- started/ended from `WorkoutSessionView` lifecycle hooks via the `WorkoutLiveActivity` facade
- refreshed in-process from the widget extension via `WorkoutLiveActivityRefresher` (no host-app round-trip required for lock-screen taps)
- defended against ghost activities via single-activity invariant + 4h orphan cleanup on bootstrap
- gracefully degraded when LA is disabled (inline banner + Settings deep-link, widget remains the fallback)

Out of scope (per spec): APNs push updates, Watch complication, rest-timer countdown, customizable layout, charts, multiple simultaneous activities.
